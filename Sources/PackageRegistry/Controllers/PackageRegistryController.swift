import Foundation
import HTTPTypes
import Hummingbird
import MultipartKit
import RegexBuilder
import Zip

extension HTTPField.Name {
    static var link: Self { .init("Link")! }
    static var digest: Self { .init("Digest")! }
    static var swiftPMSignature: Self { .init("X-Swift-Package-Signature")! }
    static var swiftPMSignatureFormat: Self { .init("X-Swift-Package-Signature-Format")! }
}

struct PackageRegistryController<PackageReleasesRepo: PackageReleaseRepository, ManifestsRepo: ManifestRepository> {
    typealias Context = PackageRegistryRequestContext

    let storage: FileStorage
    let packageRepository: PackageReleasesRepo
    let manifestRepository: ManifestsRepo
    let urlRoot: String

    func addRoutes(to group: RouterGroup<Context>) {
        group.add(middleware: VersionMiddleware(version: "1"))
        group.get("/publish-requirements", use: self.publishRequirements)
        group.get("/{scope}/{name}", use: self.list)
        group.get("/{scope}/{name}/{version}.zip", use: self.download)
        group.get("/{scope}/{name}/{version}/Package.swift", use: self.getManifest)
        group.get("/identifiers", use: self.lookupIdentifiers)
        group.get("/{scope}/{name}/{version}", use: self.getMetadata)
        group.put("/{scope}/{name}/{version}", use: self.createRelease)
        group.on("**", method: .options, use: self.options)
    }

    @Sendable func options(_: Request, context _: Context) throws -> Response {
        return .init(
            status: .ok,
            headers: [
                .allow: "GET, PUT",
                .link: "<https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md>; rel=\"service-doc\",<https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/registry.openapi.yaml>; rel=\"service-desc\"",
            ]
        )
    }

    /// Return publish requirements
    struct PublishRequirementsResponse {
        struct Metadata {
            let location = ["in-request"]
        }
        struct Signing {
            let required = false
            let acceptedSignatureFormats = ["cms-1.0.0"]
            let trustedRootCertificates: [String] = []
        }
        let metadata: Metadata = .init()
        let signing: Signing = .init()
    }
    func publishRequirements(_ request: Request, context: Context) async throws -> PublishRequirementsResponse {
        return PublishRequirementsResponse()
    }

    /// List package releases
    @Sendable func list(_ request: Request, context: Context) async throws -> EditedResponse<ListReleaseResponse> {
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
            headers[values: .link].append("<\(self.urlRoot)\(scope)/\(name)/\(latestRelease.version)>; rel=\"latest-version\"")
        }
        return .init(
            headers: headers,
            response: response
        )
    }

    /// Fetch metadata for a package release
    @Sendable func getMetadata(_ request: Request, context: Context) async throws -> EditedResponse<PackageRelease> {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let id = try PackageIdentifier(scope: scope, name: name)
        guard let release = try await packageRepository.get(id: id, version: version, logger: context.logger) else {
            throw HTTPError(.notFound)
        }
        let releases = try await packageRepository.list(id: id, logger: context.logger)
        let sortedReleases = releases.sorted { $0.version < $1.version }

        // Construct Link header
        var headers: HTTPFields = .init()
        if let latestRelease = sortedReleases.last {
            headers[values: .link].append("<\(self.urlRoot)\(scope)/\(name)/\(latestRelease.version)>; rel=\"latest-version\"")
        }
        if let index = sortedReleases.firstIndex(where: { $0.version == version }) {
            if index != sortedReleases.startIndex {
                let prevIndex = sortedReleases.index(before: index)
                let prevVersion = sortedReleases[prevIndex].version
                headers[values: .link].append("<\(self.urlRoot)\(scope)/\(name)/\(prevVersion)>; rel=\"predecessor-version\"")
            }
            let nextIndex = sortedReleases.index(after: index)
            if nextIndex != sortedReleases.endIndex {
                let nextVersion = sortedReleases[nextIndex].version
                headers[values: .link].append("<\(self.urlRoot)\(scope)/\(name)/\(nextVersion)>; rel=\"successor-version\"")
            }
        }
        return .init(headers: headers, response: release)
    }

    /// Fetch manifest for a package release
    @Sendable func getManifest(_ request: Request, context: Context) async throws -> Response {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let swiftVersion = request.uri.queryParameters.get("swift-version")

        let id = try PackageIdentifier(scope: scope, name: name)
        guard let manifests = try await self.manifestRepository.get(.init(packageId: id, version: version), logger: context.logger) else {
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
        let filename = if let manifestVersion { "Package@swift-\(manifestVersion).swift" } else { "Package.swift" }
        var headers: HTTPFields = .init()
        headers[values: .link] = manifests.versions.map { "<\(self.urlRoot)\(scope)/\(name)/\(version)/Package.swift?swift-version=\($0.swiftVersion)>; rel=\"alternate\"; filename=\"Package@swift-\($0.swiftVersion).swift\"; swift-tools-version=\"\($0.swiftVersion)\"" }
        headers[.contentType] = "text/x-swift"
        headers[.contentDisposition] = "attachment; filename=\"\(filename)\""
        headers[.cacheControl] = "public, immutable"
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
        let release = try await self.packageRepository.get(id: id, version: version, logger: context.logger)
    
        guard let release else {
            throw HTTPError(.notFound)
        }
        let responseBody = try await self.storage.readFile(filename, context: context)
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
        /*if request.headers[.expect] == "100-continue" {
            throw Problem(
                status: .expectationFailed,
                type: ProblemType.expectionsUnsupported.url,
                detail: "expectations aren't supported"
            )
        }*/
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
        let body = try await request.body.collect(upTo: .max)
        let createRequest = try FormDataDecoder().decode(CreateReleaseRequest.self, from: body, boundary: parameter.value)
        let id = try PackageIdentifier(scope: scope, name: name)
        let packageRelease = try createRequest.createRelease(id: id, version: version)
        // verify digest
        if let digest = request.headers[.digest] {
            guard digest == "sha-256=\(packageRelease.resources[0].checksum)" else {
                throw Problem(
                    status: .badRequest,
                    type: ProblemType.invalidDigest.url,
                    detail: "invalid digest"
                )
            }
        }
        // if package has signing data then verify signature header
        if packageRelease.resources[0].signing != nil {
            guard request.headers[.swiftPMSignatureFormat] == "cms-1.0.0" else  {
                throw Problem(
                    status: .badRequest,
                    type: ProblemType.invalidSignatureFormat.url,
                    detail: "invalid signature format"
                )
            }
        }
        // save release zip
        let folder = "\(scope).\(name)"
        let filename = "\(scope).\(name)/\(version).zip"
        try await storage.makeDirectory(folder, context: context)
        try await self.storage.writeFile(filename, buffer: ByteBuffer(data: createRequest.sourceArchive), context: context)
        // process zip file and extract package.swift
        let manifests = try await self.extractManifestsFromZipFile(self.storage.rootFolder + filename)
        guard let manifests else {
            throw Problem(
                status: .unprocessableContent,
                detail: "package doesn't contain a valid manifest (Package.swift) file"
            )
        }
        // save manifests
        try await self.manifestRepository.add(.init(packageId: id, version: version), manifests: manifests, logger: context.logger)
        // save release metadata
        guard try await self.packageRepository.add(packageRelease, logger: context.logger) else {
            throw Problem(
                status: .conflict,
                type: ProblemType.versionAlreadyExists.url,
                detail: "a release with version \(version) already exists"
            )
        }
        return .init(status: .created)
    }

    /// Extract manifests from zip file
    func extractManifestsFromZipFile(_ filename: String) async throws -> Manifests? {
        do {
            let zipFileManager = ZipFileManager()
            return try await zipFileManager.withZipFile(filename) { zip -> Manifests? in
                let contents = zipFileManager.contents(of: zip)
                let packageSwiftFiles = try await contents.compactMap { file -> (filename: String, position: ZipFilePosition)? in
                    let filename = file.filename
                    guard let firstSlash = filename.firstIndex(where: { $0 == "/" }) else { return nil }
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
                        manifestVersions.append(.init(manifest: fileContents, swiftVersion: version))
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

private let packageSwiftRegex = Regex {
    "/package"
    Optionally {
        "@swift-"
        Capture {
            OneOrMore(.anyOf("0123456789."))
        }
    }
    ".swift"
}.ignoresCase()

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
