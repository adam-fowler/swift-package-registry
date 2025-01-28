import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import Jobs
import Logging
import NIOCore
import NIOFoundationCompat
import NIOPosix
import RegexBuilder
import X509
import ZipArchive

struct PublishPackageJob: JobParameters {
    static var jobName: String { "PackageRegistry:Publish" }

    let id: PackageIdentifier
    let publishRequestID: String
    let version: Version
    let sourceArchiveFile: String
    let sourceArchiveDigest: String
    let sourceArchiveSignature: Data?
    let metadata: Data?
    let metadataSignature: Data?
}

struct PackageSignatureVerification {
    let trustedRoots: [Certificate]
    let allowUntrustedCertificates: Bool

    init(
        trustedRoots: [[UInt8]],
        allowUntrustedCertificates: Bool
    ) throws {
        self.trustedRoots = try trustedRoots.map { try Certificate(derEncoded: $0) }
        self.allowUntrustedCertificates = allowUntrustedCertificates
    }

    var verifierConfiguration: VerifierConfiguration {
        .init(
            trustedRoots: trustedRoots,
            includeDefaultTrustRoots: true,
            certificateExpiration: .enabled(validationTime: .now),
            certificateRevocation: .allowSoftFail(validationTime: .now)
        )
    }
}

struct PublishJobController<
    PackageReleasesRepo: PackageReleaseRepository,
    ManifestsRepo: ManifestRepository,
    KeyValueStore: PersistDriver
> {
    let storage: LocalFileStorage
    let packageRepository: PackageReleasesRepo
    let manifestRepository: ManifestsRepo
    let publishStatusManager: PublishStatusManager<KeyValueStore>
    let httpClient: HTTPClient
    let packageSignatureVerification: PackageSignatureVerification

    func registerJobs(jobQueue: JobQueue<some JobQueueDriver>) {
        jobQueue.registerJob(execute: publishPackageJob)
    }

    func publishPackageJob(parameters: PublishPackageJob, context: JobContext) async throws {
        do {
            // verify signatures
            try await verifySignature(parameters.sourceArchiveSignature, logger: context.logger)
            try await verifySignature(parameters.metadataSignature, content: parameters.metadata, logger: context.logger)

            // create package release
            let packageRelease = try self.createRelease(parameters: parameters)

            // process zip file and extract package.swift
            let manifests = try await self.extractManifestsFromZipFile(
                self.storage.rootFolder + parameters.sourceArchiveFile,
                logger: context.logger
            )
            guard let manifests else {
                throw Problem(
                    status: HTTPResponse.Status.unprocessableContent,
                    detail: "Package doesn't contain a valid manifest (Package.swift) file"
                )
            }
            // save release metadata
            guard try await self.packageRepository.add(packageRelease, logger: context.logger) else {
                throw Problem(
                    status: HTTPResponse.Status.conflict,
                    type: ProblemType.versionAlreadyExists.url,
                    detail: "A release with version \(parameters.version) already exists"
                )
            }
            // save manifests
            try await self.manifestRepository.add(
                .init(packageId: parameters.id, version: parameters.version),
                manifests: manifests,
                logger: context.logger
            )
            // set as successful
            try await publishStatusManager.set(
                id: parameters.publishRequestID,
                status: .success("\(parameters.id.scope)/\(parameters.id.name)/\(parameters.version)")
            )
        } catch let error as Problem {
            context.logger.debug("Publish failed: \(error.detail ?? "No details")")
            try await publishStatusManager.set(
                id: parameters.publishRequestID,
                status: .failed(
                    .init(
                        status: error.status.code,
                        url: error.type,
                        detail: error.detail
                    )
                )
            )

        }
    }

    func createRelease(parameters: PublishPackageJob) throws -> PackageRelease {
        let resource = PackageRelease.Resource(
            name: "source-archive",
            type: "application/zip",
            checksum: parameters.sourceArchiveDigest,
            signing: parameters.sourceArchiveSignature.map {
                .init(signatureBase64Encoded: $0.base64EncodedString(), signatureFormat: "cms-1.0.0")
            }
        )
        guard let metadata = parameters.metadata else {
            throw Problem(status: .unprocessableContent, detail: "Release metadata is required to publish release.")
        }
        var packageMetadata: PackageMetadata
        do {
            packageMetadata = try JSONDecoder().decode(PackageMetadata.self, from: metadata)
            if let repositoryURLs = packageMetadata.repositoryURLs {
                packageMetadata.repositoryURLs = repositoryURLs.map { $0.standardizedGitURL() }
            }
        } catch {
            throw Problem(status: .unprocessableContent, detail: "Invalid JSON provided for release metadata.")
        }
        return .init(
            id: parameters.id,
            version: parameters.version,
            resources: [resource],
            metadata: packageMetadata,
            publishedAt: Date.now.formatted(.iso8601)
        )
    }

    func verifySignature(_ signatureBytes: Data?, content: Data? = nil, logger: Logger) async throws {
        guard let signatureBytes else { return }

        do {
            let signatureProvider = CMSSignatureProvider(httpClient: self.httpClient)
            if let content {
                let value = try await signatureProvider.verify(
                    signatureBytes: [UInt8](signatureBytes),
                    content: content,
                    verifierConfiguration: packageSignatureVerification.verifierConfiguration
                )
                logger.debug("Data signed with \(value)")

            } else {
                let value = try await signatureProvider.status(
                    signatureBytes: [UInt8](signatureBytes),
                    verifierConfiguration: packageSignatureVerification.verifierConfiguration
                )
                logger.debug("Data signed with \(value)")
            }
        } catch {
            switch error {
            case .invalid(let string):
                throw Problem(
                    status: HTTPResponse.Status.unprocessableContent,
                    detail: "Provided signature data is invalid: \(string)"
                )
            case .signatureInvalid(let string):
                throw Problem(
                    status: HTTPResponse.Status.unprocessableContent,
                    detail: "Provided signature is invalid: \(string)"
                )
            case .certificateInvalid(let string):
                throw Problem(
                    status: HTTPResponse.Status.unprocessableContent,
                    detail: "Provided signature's certificate is invalid: \(string)"
                )
            case .certificateNotTrusted(let signingEntity):
                if self.packageSignatureVerification.allowUntrustedCertificates {
                    logger.debug("Data signed with untrusted certificate \(signingEntity)")
                } else {
                    throw Problem(
                        status: HTTPResponse.Status.unprocessableContent,
                        detail: "Package signed with untrusted certificate \(signingEntity)"
                    )
                }
            }
        }
    }

    /// Extract manifests from zip file
    func extractManifestsFromZipFile(_ filename: String, logger: Logger) async throws -> Manifests? {
        do {
            return try await NIOThreadPool.singleton.runIfActive {
                let packageSwiftRegex = Regex {
                    "/package"
                    Optionally {
                        "@swift-"
                        Capture {
                            OneOrMore(.anyOf("0123456789"))
                        }
                        "."
                        Capture {
                            OneOrMore(.anyOf("0123456789"))
                        }
                    }
                    ".swift"
                }.ignoresCase()

                var manifestVersions: [Manifests.Version] = []
                var defaultManifest: ByteBuffer?

                try ZipArchiveReader.withFile(filename) { zipArchiveReader in
                    let directory = try zipArchiveReader.readDirectory()
                    let packageSwiftFiles = directory.compactMap { file -> Zip.FileHeader? in
                        // drop enclosing directory
                        let filename = file.filename.drop { $0 != "/" }.lowercased()
                        if filename == "/package.swift" || filename.hasPrefix("/package@swift-") {
                            return file
                        } else {
                            return nil
                        }
                    }

                    for file in packageSwiftFiles {
                        // drop enclosing directory
                        let filename = file.filename.drop { $0 != "/" }.lowercased()
                        if filename == "/package.swift" {
                            defaultManifest = .init(bytes: try zipArchiveReader.readFile(file))
                        } else if let match = filename.wholeMatch(of: packageSwiftRegex),
                            let major = match.output.1, let minor = match.output.2
                        {
                            let version = String("\(major).\(minor)")
                            let fileContents = ByteBuffer(bytes: try zipArchiveReader.readFile(file))
                            manifestVersions.append(
                                .init(manifest: fileContents, swiftVersion: version)
                            )
                            logger.debug("Found Package.swift manifest", metadata: ["filename": .string(filename)])
                        } else {
                            throw Problem(
                                status: HTTPResponse.Status.unprocessableContent,
                                detail: "Failed to extract swift version from: \(filename)"
                            )
                        }
                    }
                }
                guard let defaultManifest else { return nil }
                return .init(default: defaultManifest, versions: manifestVersions)
            }
        } catch {
            throw Problem(status: .internalServerError, detail: "\(error)")
        }
    }
}

extension AsyncSequence {
    // Collect contents of AsyncSequence into Array
    func collect(maxElements: Int) async throws -> [Element] {
        var count = 0
        var array: [Element] = []
        for try await element in self {
            if count >= maxElements {
                break
            }
            array.append(element)
            count += 1
        }
        return array
    }
}
