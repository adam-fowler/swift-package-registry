import Foundation
import HTTPTypes
import Hummingbird
import Jobs
import NIOCore
import NIOFoundationCompat
import RegexBuilder
import Zip

struct PublishJob: JobParameters {
    static var jobName: String { "PackageRegistry: Publish" }

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
        jobQueue.registerJob(parameters: PublishJob.self) { (parameters: PublishJob, context: JobContext) -> Void in
            let createRequest = CreateReleaseRequest(
                sourceArchiveDigest: parameters.sourceArchiveDigest,
                sourceArchiveSignature: parameters.sourceArchiveSignature,
                metadata: parameters.metadata,
                metadataSignature: parameters.metadataSignature
            )
            let packageRelease = try createRequest.createRelease(id: parameters.id, version: parameters.version)

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
