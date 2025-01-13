import Foundation
import HTTPTypes
import Hummingbird
import Jobs
import NIOCore
import NIOFoundationCompat
import RegexBuilder
import Zip

struct PublishPackageJob: JobParameters {
    static var jobName: String { "PackageRegistry:Publish" }

    let id: PackageIdentifier
    let publishRequestID: String
    let version: Version
    let sourceArchiveFile: String
    let sourceArchiveDigest: String
    let sourceArchiveSignature: String?
    let metadata: Data?
    let metadataSignature: String?
}

struct PublishJobController<PackageReleasesRepo: PackageReleaseRepository, ManifestsRepo: ManifestRepository, KeyValueStore: PersistDriver> {
    let storage: LocalFileStorage
    let packageRepository: PackageReleasesRepo
    let manifestRepository: ManifestsRepo
    let publishStatusManager: PublishStatusManager<KeyValueStore>

    func registerJobs(jobQueue: JobQueue<some JobQueueDriver>) {
        jobQueue.registerJob(execute: publishPackageJob)
    }

    func publishPackageJob(parameters: PublishPackageJob, context: JobContext) async throws {
        let packageRelease = try self.createRelease(parameters: parameters)

        // process zip file and extract package.swift
        let manifests = try await self.extractManifestsFromZipFile(
            self.storage.rootFolder + parameters.sourceArchiveFile
        )
        guard let manifests else {
            try await publishStatusManager.set(
                id: parameters.publishRequestID,
                status: .failed(
                    .init(
                        status: HTTPResponse.Status.unprocessableContent.code,
                        details: "package doesn't contain a valid manifest (Package.swift) file"
                    )
                )
            )
            return
        }
        // save release metadata
        guard try await self.packageRepository.add(packageRelease, logger: context.logger) else {
            try await publishStatusManager.set(
                id: parameters.publishRequestID,
                status: .failed(
                    .init(
                        status: HTTPResponse.Status.conflict.code,
                        url: ProblemType.versionAlreadyExists.url,
                        details: "a release with version \(parameters.version) already exists"
                    )
                )
            )
            return
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
    }

    func createRelease(parameters: PublishPackageJob) throws -> PackageRelease {
        let resource = PackageRelease.Resource(
            name: "source-archive",
            type: "application/zip",
            checksum: parameters.sourceArchiveDigest,
            signing: parameters.sourceArchiveSignature.map {
                .init(signatureBase64Encoded: $0, signatureFormat: "cms-1.0.0")
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
            throw Problem(status: .unprocessableContent, detail: "invalid JSON provided for release metadata.")
        }
        return .init(
            id: parameters.id,
            version: parameters.version,
            resources: [resource],
            metadata: packageMetadata,
            publishedAt: Date.now.formatted(.iso8601)
        )
    }

    /// Extract manifests from zip file
    func extractManifestsFromZipFile(_ filename: String) async throws -> Manifests? {
        let packageSwiftRegex = Regex {
            "/package"
            Optionally {
                "@swift-"
                Capture {
                    OneOrMore(.anyOf("0123456789."))
                }
            }
            ".swift"
        }.ignoresCase()

        do {
            let zipFileManager = ZipFileManager()
            return try await zipFileManager.withZipFile(filename) { zip -> Manifests? in
                let contents = zipFileManager.contents(of: zip)
                let packageSwiftFiles = try await contents.compactMap {
                    file -> (filename: String, position: ZipFilePosition)? in
                    let filename = file.filename
                    guard let firstSlash = filename.firstIndex(where: { $0 == "/" }) else {
                        return nil
                    }
                    let filename2 = filename[firstSlash...].lowercased()
                    if filename2 == "/package.swift" || filename2.hasPrefix("/package@swift-") {
                        return (filename: filename2, position: file.position)
                    } else {
                        return nil
                    }
                }.collect(maxElements: .max)
                var manifestVersions: [Manifests.Version] = []
                var defaultManifest: ByteBuffer?
                for file in packageSwiftFiles {
                    if file.filename == "/package.swift" {
                        defaultManifest = try await zipFileManager.loadFile(zip, at: file.position)
                    } else if let v = file.filename.wholeMatch(of: packageSwiftRegex)?.output.1 {
                        let version = String(v)
                        let fileContents = try await zipFileManager.loadFile(zip, at: file.position)
                        manifestVersions.append(
                            .init(manifest: fileContents, swiftVersion: version)
                        )
                    } else {
                        continue
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
