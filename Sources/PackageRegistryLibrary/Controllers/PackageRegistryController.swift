import Crypto
import Foundation
import HTTPTypes
import Hummingbird
import Jobs
import MultipartKit
import NIOFoundationCompat
import RegexBuilder
import StructuredFieldValues

public struct PackageRegistryController<
    Context: PackageRegistryRequestContext,
    RegistryStorage: FileStorage,
    PackageReleasesRepo: PackageReleaseRepository,
    ManifestsRepo: ManifestRepository,
    JQD: JobQueueDriver,
    KeyValueStore: PersistDriver
>: Sendable {
    let storage: RegistryStorage
    let packageRepository: PackageReleasesRepo
    let manifestRepository: ManifestsRepo
    let urlRoot: String
    let jobQueue: JobQueue<JQD>
    let publishStatusManager: PublishStatusManager<KeyValueStore>

    public init(
        storage: RegistryStorage,
        packageRepository: PackageReleasesRepo,
        manifestRepository: ManifestsRepo,
        urlRoot: String,
        jobQueue: JobQueue<JQD>,
        publishStatusManager: PublishStatusManager<KeyValueStore>
    ) {
        self.storage = storage
        self.packageRepository = packageRepository
        self.manifestRepository = manifestRepository
        self.urlRoot = urlRoot
        self.jobQueue = jobQueue
        self.publishStatusManager = publishStatusManager
    }

    // Routes with authentication
    public func routes(users: some UserRepository) -> RouteCollection<Context> {
        let routes = RouteCollection(context: Context.self)
        routes.add(middleware: ProblemMiddleware())
        routes.group()
            .add(middleware: BasicAuthenticator(repository: users))
            .post("/", use: self.login)
        routes.add(middleware: VersionMiddleware(version: "1"))
        routes.get("/submissions/{id}", use: self.createReleaseStatus)
        routes.get("/{scope}/{name}", use: self.list)
        routes.get("/{scope}/{name}/{version}.zip", use: self.download)
        routes.get("/{scope}/{name}/{version}/Package.swift", use: self.getManifest)
        routes.get("/identifiers", use: self.lookupIdentifiers)
        routes.get("/{scope}/{name}/{version}", use: self.getMetadata)
        routes.group()
            .add(middleware: BasicAuthenticator(repository: users))
            .put("/{scope}/{name}/{version}", use: self.createRelease)
        return routes
    }

    // Routes without authentication
    public func routes() -> RouteCollection<Context> {
        let routes = RouteCollection(context: Context.self)
        routes.add(middleware: VersionMiddleware(version: "1"))
        routes.get("/submissions/{id}", use: self.createReleaseStatus)
        routes.get("/{scope}/{name}", use: self.list)
        routes.get("/{scope}/{name}/{version}.zip", use: self.download)
        routes.get("/{scope}/{name}/{version}/Package.swift", use: self.getManifest)
        routes.get("/identifiers", use: self.lookupIdentifiers)
        routes.get("/{scope}/{name}/{version}", use: self.getMetadata)
        routes.put("/{scope}/{name}/{version}", use: self.createRelease)
        return routes
    }

    @Sendable func login(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        _ = try context.requireIdentity()
        return .ok
    }

    /// List package releases
    @Sendable func list(
        _ request: Request,
        context: Context
    ) async throws -> EditedResponse<ListReleaseResponse> {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let id = try PackageIdentifier(scope: scope, name: name)
        let releases = try await self.packageRepository.list(id: id, logger: context.logger)
        guard releases.count > 0 else { throw HTTPError(.notFound) }
        let releasesResponse = releases.compactMap {
            if $0.status.shoudBeListed {
                return (
                    $0.version.description,
                    ListReleaseResponse.Release(
                        url: "\(self.urlRoot)\(scope)/\(name)/\($0.version)",
                        problem: $0.status.problem
                    )
                )
            } else {
                return nil
            }
        }
        let response = ListReleaseResponse(releases: .init(releasesResponse) { first, _ in first })
        var headers: HTTPFields = .init()
        if let latestRelease = releases.max(by: { $0.version < $1.version }) {
            let linkHeader = LinkHeader(items: [
                .init(item: "<\(self.urlRoot)\(scope)/\(name)/\(latestRelease.version)>", parameters: ["rel": "latest-version"])
            ])
            try headers[values: .link].append(StructuredFieldValueEncoder().encodeAsString(linkHeader))
        }
        return .init(
            headers: headers,
            response: response
        )
    }

    /// Fetch metadata for a package release
    @Sendable func getMetadata(
        _ request: Request,
        context: Context
    ) async throws -> EditedResponse<PackageRelease> {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let id = try PackageIdentifier(scope: scope, name: name)
        guard
            let release = try await packageRepository.get(
                id: id,
                version: version,
                logger: context.logger
            )
        else {
            throw HTTPError(.notFound)
        }
        let releases = try await packageRepository.list(id: id, logger: context.logger)
        let sortedReleases = releases.sorted { $0.version < $1.version }

        // Construct Link header
        var linkHeader = LinkHeader(items: [])
        if let latestRelease = sortedReleases.last {
            linkHeader.items.append(
                .init(item: "<\(self.urlRoot)\(scope)/\(name)/\(latestRelease.version)>", parameters: ["rel": "latest-version"])
            )
        }
        if let index = sortedReleases.firstIndex(where: { $0.version == version }) {
            if index != sortedReleases.startIndex {
                let prevIndex = sortedReleases.index(before: index)
                let prevVersion = sortedReleases[prevIndex].version
                linkHeader.items.append(
                    .init(item: "<\(self.urlRoot)\(scope)/\(name)/\(prevVersion)>", parameters: ["rel": "predecessor-version"])
                )
            }
            let nextIndex = sortedReleases.index(after: index)
            if nextIndex != sortedReleases.endIndex {
                let nextVersion = sortedReleases[nextIndex].version
                linkHeader.items.append(
                    .init(item: "<\(self.urlRoot)\(scope)/\(name)/\(nextVersion)>", parameters: ["rel": "successor-version"])
                )
            }
        }
        let headers: HTTPFields = [
            .link: try StructuredFieldValueEncoder().encodeAsString(linkHeader)
        ]
        return .init(headers: headers, response: release)
    }

    /// Fetch manifest for a package release
    @Sendable func getManifest(_ request: Request, context: Context) async throws -> Response {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let swiftVersion = request.uri.queryParameters.get("swift-version")

        let id = try PackageIdentifier(scope: scope, name: name)
        guard
            let manifests = try await self.manifestRepository.get(
                .init(packageId: id, version: version),
                logger: context.logger
            )
        else {
            return .init(status: .notFound)
        }
        let manifest: ByteBuffer
        var manifestVersion: String?
        if let swiftVersion {
            let foundManifest = manifests.versions.first { $0.swiftVersion == swiftVersion }
            manifest = foundManifest?.manifest ?? manifests.default
            manifestVersion = foundManifest?.swiftVersion
        } else {
            manifest = manifests.default
        }
        let filename =
            if let manifestVersion { "Package@swift-\(manifestVersion).swift" } else {
                "Package.swift"
            }
        let linkHeader = LinkHeader(
            items:
                manifests.versions.map {
                    .init(
                        item: "<\(self.urlRoot)\(scope)/\(name)/\(version)/Package.swift?swift-version=\($0.swiftVersion)>",
                        parameters: [
                            "rel": "alternate",
                            "filename": "Package@swift-\($0.swiftVersion).swift",
                            "swift-tools-version": "\($0.swiftVersion)",
                        ]
                    )
                }
        )
        var headers: HTTPFields = [
            .contentType: "text/x-swift",
            .contentDisposition: "attachment; filename=\"\(filename)\"",
            .cacheControl: "public, immutable",
        ]
        if linkHeader.items.count > 0 {
            headers[.link] = try StructuredFieldValueEncoder().encodeAsString(linkHeader)
        }
        return .init(status: .ok, headers: headers, body: .init(byteBuffer: manifest))
    }

    /// Download source archive for a package release
    @Sendable func download(_: Request, context: Context) async throws -> Response {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let filename = "\(scope).\(name)/\(version).zip"

        // get metadata
        let id = try PackageIdentifier(scope: scope, name: name)
        let release = try await self.packageRepository.get(
            id: id,
            version: version,
            logger: context.logger
        )

        guard let release else {
            throw HTTPError(.notFound)
        }
        let responseBody = ResponseBody { writer in
            try await self.storage.readFile(filename) { buffer in
                try await writer.write(buffer)
            }
            try await writer.finish(nil)
        }
        var headers: HTTPFields = [
            .contentType: MediaType.applicationZip.description,
            .contentDisposition: "attachment; filename=\"\(name)-\(version).zip\"",
            .cacheControl: "public, immutable",
        ]
        if let resource = release.resources.first(where: { $0.name == "source-archive" }) {
            headers[.digest] = "sha256=\(resource.checksum)"
            if let signing = resource.signing {
                headers[.swiftPMSignature] = signing.signatureBase64Encoded
                headers[.swiftPMSignatureFormat] = signing.signatureFormat
            }
        }
        return .init(
            status: .ok,
            headers: headers,
            body: responseBody
        )
    }

    struct Identifiers: ResponseEncodable {
        let identifiers: [PackageIdentifier]
    }

    /// Lookup package identifiers registered for a URL
    @Sendable func lookupIdentifiers(request: Request, context: Context) async throws -> Identifiers {
        var url = try request.uri.queryParameters.require("url")
        url = url.standardizedGitURL()
        let identifiers = try await self.packageRepository.query(url: url, logger: context.logger)
        guard identifiers.count > 0 else {
            throw HTTPError(.notFound)
        }
        return .init(identifiers: identifiers)
    }

    /// Create a package release
    @Sendable func createRelease(_ request: Request, context: Context) async throws -> Response {
        _ = try context.requireIdentity()
        /* if request.headers[.expect] == "100-continue" {
             throw Problem(
                 status: .expectationFailed,
                 type: ProblemType.expectionsUnsupported.url,
                 detail: "expectations aren't supported"
             )
         } */
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        guard let contentType = request.headers[.contentType],
            let mediaType = MediaType(from: contentType),
            case .multipartForm = mediaType,
            let parameter = mediaType.parameter,
            parameter.name == "boundary"
        else {
            throw Problem(
                status: .badRequest,
                type: ProblemType.invalidContentType.url,
                detail: "invalid content type"
            )
        }
        let id = try PackageIdentifier(scope: scope, name: name)
        // verify package release hasn't been published already
        guard try await self.packageRepository.get(id: id, version: version, logger: context.logger) == nil
        else {
            throw Problem(
                status: .conflict,
                type: ProblemType.versionAlreadyExists.url,
                detail: "a release with version \(version) already exists"
            )
        }

        let sourceArchiveFolder = "\(id)"
        let sourceArchiveFilename = "\(id)/\(version).zip"

        /// Parse multipart file, extracting metadata, saving source archive to disk
        let multipartStream = StreamingMultipartParserAsyncSequence(boundary: parameter.value, buffer: request.body.map { $0.readableBytesView })
        var iterator = multipartStream.makeAsyncIterator()
        do {
            guard case .boundary = try await iterator.next() else { throw HTTPError(.badRequest) }
        } catch {
            throw HTTPError(.badRequest)
        }

        var sourceArchiveDigest: SHA256Digest?
        var sourceArchiveSignature: ByteBuffer?
        var metadata: ByteBuffer?
        var metadataSignature: ByteBuffer?

        loop: while true {
            switch try await iterator.next() {
            case .headerFields(let headers):
                guard let contentDispositionString = headers[values: .contentDisposition].first else { throw HTTPError(.badRequest) }
                guard
                    let contentDisposition = try? StructuredFieldValueDecoder().decode(
                        MultipartContentDispostion.self,
                        from: contentDispositionString
                    )
                else { throw HTTPError(.badRequest) }
                switch contentDisposition.parameters.name {
                case "source-archive":
                    try await storage.makeDirectory(sourceArchiveFolder)
                    let multipartBodyAsyncSequence = MultipartBodyAsyncSequence(multipartIterator: iterator)
                    let sha256CalculatingAsyncSequence = ProcessingAsyncSequence(multipartBodyAsyncSequence, state: SHA256()) { buffer, sha256 in
                        sha256.update(data: buffer.readableBytesView)
                    }
                    try await self.storage.writeFile(sourceArchiveFilename, contents: sha256CalculatingAsyncSequence)
                    sourceArchiveDigest = sha256CalculatingAsyncSequence.state.finalize()
                    iterator = multipartBodyAsyncSequence.multipartIterator
                case "metadata":
                    guard let metaDataPart = try await iterator.nextCollatedPart() else { throw HTTPError(.badRequest) }
                    guard case .bodyChunk(let bufferView) = metaDataPart else { throw HTTPError(.badRequest) }
                    metadata = ByteBuffer(bufferView)
                case "source-archive-signature":
                    guard let metaDataPart = try await iterator.nextCollatedPart() else { throw HTTPError(.badRequest) }
                    guard case .bodyChunk(let bufferView) = metaDataPart else { throw HTTPError(.badRequest) }
                    sourceArchiveSignature = ByteBuffer(bufferView)
                case "metadata-signature":
                    guard let metaDataPart = try await iterator.nextCollatedPart() else { throw HTTPError(.badRequest) }
                    guard case .bodyChunk(let bufferView) = metaDataPart else { throw HTTPError(.badRequest) }
                    metadataSignature = ByteBuffer(bufferView)
                default:
                    throw HTTPError(.badRequest, message: "Unexpected part in multipart file")
                }

            case .bodyChunk:
                throw HTTPError(.badRequest, message: "Unexpected body chunk")

            case .boundary:
                break

            case .none:
                break loop
            }
        }
        guard let sourceArchiveDigest else { throw HTTPError(.badRequest, message: "No source-archive part") }
        let sourceArchiveDigestHex = sourceArchiveDigest.hexDigest()

        // verify digest
        if let digest = request.headers[.digest] {
            guard digest == "sha-256=\(sourceArchiveDigestHex)" else {
                throw Problem(
                    status: .badRequest,
                    type: ProblemType.invalidDigest.url,
                    detail: "invalid digest"
                )
            }
        }
        // if package has signing data then verify signature header
        if sourceArchiveSignature != nil || metadataSignature != nil {
            guard request.headers[.swiftPMSignatureFormat] == "cms-1.0.0" else {
                throw Problem(
                    status: .badRequest,
                    type: ProblemType.invalidSignatureFormat.url,
                    detail: "invalid signature format"
                )
            }
        }
        let metadataData = metadata.map { Data(buffer: $0, byteTransferStrategy: .noCopy) }
        let metadataSignatureData = metadataSignature.map { Data(buffer: $0, byteTransferStrategy: .noCopy) }
        let sourceArchiveSignatureData = sourceArchiveSignature.map { Data(buffer: $0, byteTransferStrategy: .noCopy) }

        let packageRelease = try createRelease(
            id: id,
            version: version,
            metadata: metadataData,
            sourceArchiveDigest: sourceArchiveDigestHex,
            sourceArchiveSignature: sourceArchiveSignatureData
        )
        // save release metadata
        guard try await self.packageRepository.add(packageRelease, status: .processing, logger: context.logger) else {
            throw Problem(
                status: HTTPResponse.Status.conflict,
                type: ProblemType.versionAlreadyExists.url,
                detail: "A release with version \(version) already exists"
            )
        }

        // push publish release job
        let requestId = UUID().uuidString
        try await self.jobQueue.push(
            PublishPackageJob(
                id: id,
                publishRequestID: requestId,
                version: version,
                sourceArchiveFile: sourceArchiveFilename,
                sourceArchiveDigest: sourceArchiveDigestHex,
                sourceArchiveSignature: sourceArchiveSignatureData,
                metadata: metadataData,
                metadataSignature: metadataSignatureData
            )
        )
        try await self.publishStatusManager.set(id: requestId, status: .inProgress)
        return Response(
            status: .accepted,
            headers: [
                .location: "\(self.urlRoot)submissions/\(requestId)",
                .retryAfter: "5",
            ]
        )
    }

    func createRelease(
        id: PackageIdentifier,
        version: Version,
        metadata: Data?,
        sourceArchiveDigest: String,
        sourceArchiveSignature: Data?
    ) throws -> PackageRelease {
        let resource = PackageRelease.Resource(
            name: "source-archive",
            type: "application/zip",
            checksum: sourceArchiveDigest,
            signing: sourceArchiveSignature.map {
                .init(signatureBase64Encoded: $0.base64EncodedString(), signatureFormat: "cms-1.0.0")
            }
        )
        guard let metadata = metadata else {
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
            id: id,
            version: version,
            resources: [resource],
            metadata: packageMetadata,
            publishedAt: Date.now.formatted(.iso8601)
        )
    }

    /// Return status of a create package release job
    @Sendable func createReleaseStatus(_ request: Request, context: Context) async throws -> Response {
        let id = try context.parameters.require("id")
        guard let status = try await self.publishStatusManager.get(id: id) else {
            throw Problem(
                status: .badRequest,
                detail: "invalid package"
            )
        }
        switch status {
        case .inProgress:
            return Response(status: .accepted, headers: [.retryAfter: "5"])

        case .failed(let problem):
            throw Problem(
                status: .init(code: problem.status),
                type: problem.url,
                detail: problem.detail
            )

        case .success(let address):
            return .redirect(to: "\(self.urlRoot)\(address)", type: .permanent)
        }
    }
}
