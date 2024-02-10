import Foundation
import HTTPTypes
import Hummingbird
import MultipartKit
import RegexBuilder
import Zip

extension HTTPField.Name {
    static var link: Self { .init("Link")! }
    static var digest: Self { .init("Digest")! }
}

struct PackageRegistryController<PackageReleases: PackageReleaseRepository, Manifests: ManifestRepository> {
    typealias Context = RequestContext

    let storage: FileStorage
    let packageRepository: PackageReleases
    let manifestRepository: Manifests

    func addRoutes(to group: HBRouterGroup<Context>) {
        group.get("/{scope}/{name}", use: self.list)
        group.get("/{scope}/{name}/{version}.zip", use: self.download)
        group.get("/{scope}/{name}/{version}/Package.swift", use: self.getManifest)
        group.get("/identifiers", use: self.lookupIdentifiers)
        group.get("/{scope}/{name}/{version}", use: self.getMetadata)
        group.put("/{scope}/{name}/{version}", use: self.createRelease)
        group.on("**", method: .options, use: self.options)
    }

    @Sendable func options(_: HBRequest, context _: Context) async throws -> HBResponse {
        return .init(
            status: .ok,
            headers: [
                .allow: "GET, PUT",
                .link: "<https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md>; rel=\"service-doc\",<https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/registry.openapi.yaml>; rel=\"service-desc\"",
            ]
        )
    }

    /// List package releases
    @Sendable func list(_: HBRequest, context: Context) async throws -> HBEditedResponse<ListReleaseResponse> {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let id = try PackageIdentifier(scope: scope, name: name)
        let releases = try await packageRepository.list(id: id)
        guard releases.count > 0 else { throw HBHTTPError(.notFound) }
        let releasesResponse = releases.compactMap {
            if $0.status.shoudBeListed {
                return (
                    $0.version.description,
                    ListReleaseResponse.Release(
                        url: "https://localhost:8080/repository/\(scope)/\(name)/\($0.version)",
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
            headers[values: .link].append("<https://localhost:8080/repository/\(scope)/\(name)/\(latestRelease.version)>; rel=\"latest-version\"")
        }
        return .init(
            headers: headers,
            response: response
        )
    }

    /// Fetch metadata for a package release
    @Sendable func getMetadata(_: HBRequest, context: Context) async throws -> HBEditedResponse<PackageRelease> {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let id = try PackageIdentifier(scope: scope, name: name)
        guard let release = try await packageRepository.get(id: id, version: version) else {
            throw HBHTTPError(.notFound)
        }
        let releases = try await packageRepository.list(id: id)
        let sortedReleases = releases.sorted { $0.version < $1.version }

        // Construct Link header
        var headers: HTTPFields = .init()
        if let latestRelease = sortedReleases.last {
            headers[values: .link].append("<https://localhost:8080/repository/\(scope)/\(name)/\(latestRelease.version)>; rel=\"latest-version\"")
        }
        if let index = sortedReleases.firstIndex(where: { $0.version == version }) {
            if index != sortedReleases.startIndex {
                let prevIndex = sortedReleases.index(before: index)
                let prevVersion = sortedReleases[prevIndex].version
                headers[values: .link].append("<https://localhost:8080/repository/\(scope)/\(name)/\(prevVersion)>; rel=\"predecessor-version\"")
            }
            let nextIndex = sortedReleases.index(after: index)
            if nextIndex != sortedReleases.endIndex {
                let nextVersion = sortedReleases[nextIndex].version
                headers[values: .link].append("<https://localhost:8080/repository/\(scope)/\(name)/\(nextVersion)>; rel=\"successor-version\"")
            }
        }
        return .init(headers: headers, response: release)
    }

    /// Fetch manifest for a package release
    @Sendable func getManifest(_ request: HBRequest, context: Context) async throws -> HBResponse {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let swiftVersion = request.uri.queryParameters.get("swift-version")

        let id = try PackageIdentifier(scope: scope, name: name)
        guard let manifests = try await manifestRepository.get(.init(packageId: id, version: version)) else {
            return .init(status: .notFound)
        }
        let manifest: ManifestVersion?
        if let swiftVersion {
            manifest = manifests.first { $0.swiftVersion == swiftVersion } ?? manifests.first { $0.swiftVersion == nil }
        } else {
            manifest = manifests.first { $0.swiftVersion == swiftVersion } ?? manifests.first { $0.swiftVersion == nil }
        }
        guard let manifest else {
            return .init(status: .notFound)
        }
        let filename = if let version = manifest.swiftVersion { "Package@swift-\(version).swift" } else { "Package.swift" }
        let alternateVersions = manifests.compactMap(\.swiftVersion)
        var headers: HTTPFields = .init()
        headers[values: .link] = alternateVersions.map { "<https://localhost:8080/repository/\(scope)/\(name)/\(version)/Package.swift?swift-version=\($0)>; rel=\"alternate\"; filename=\"Package@swift-\($0).swift\"; swift-tools-version=\"\($0)\"" }
        headers[.contentType] = "text/x-swift"
        headers[.contentDisposition] = "attachment; filename=\"\(filename)\""
        headers[.cacheControl] = "public, immutable"
        return .init(status: .ok, headers: headers, body: .init(byteBuffer: manifest.manifest))
    }

    /// Download source archive for a package release
    @Sendable func download(_: HBRequest, context: Context) async throws -> HBResponse {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let filename = "\(scope).\(name)/\(version).zip"

        // get metadata
        let id = try PackageIdentifier(scope: scope, name: name)
        guard let release = try await try await packageRepository.get(id: id, version: version) else {
            throw HBHTTPError(.notFound)
        }
        let digest = release.resources.first { $0.name == "source-archive" }?.checksum
        let responseBody = try await self.storage.readFile(filename, context: context)
        var headers: HTTPFields = [
            .contentType: HBMediaType.applicationZip.description,
            .contentDisposition: "attachment; filename=\"\(name)-\(version).zip\"",
            .cacheControl: "public, immutable",
        ]
        if let digest {
            headers[.digest] = "sha256=\(digest)"
        }
        return .init(
            status: .ok,
            headers: headers,
            body: responseBody
        )
    }

    struct Identifiers: HBResponseEncodable {
        let identifiers: [PackageIdentifier]
    }

    /// Lookup package identifiers registered for a URL
    @Sendable func lookupIdentifiers(request: HBRequest, context: Context) async throws -> Identifiers {
        var url = try request.uri.queryParameters.require("url")
        url = url.standardizedGitURL()
        let identifiers = try await self.packageRepository.query(url: url)
        guard identifiers.count > 0 else {
            throw HBHTTPError(.notFound)
        }
        return .init(identifiers: identifiers)
    }

    /// Create a package release
    @Sendable func createRelease(_ request: HBRequest, context: Context) async throws -> HBResponse {
        if request.headers[.expect] == "100 (Continue)" {
            throw Problem(
                status: .expectationFailed,
                type: ProblemType.expectionsUnsupported.url,
                detail: "expectations aren't supported"
            )
        }
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        guard let contentType = request.headers[.contentType],
              let mediaType = HBMediaType(from: contentType),
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
        // save release zip
        let folder = "\(scope).\(name)"
        let filename = "\(scope).\(name)/\(version).zip"
        try await storage.makeDirectory(folder, context: context)
        try await self.storage.writeFile(filename, buffer: ByteBuffer(data: createRequest.sourceArchive), context: context)
        // process zip file and extract package.swift
        let manifests = try await self.extractManifestsFromZipFile(self.storage.rootFolder + filename)
        guard manifests.count > 0 else {
            throw Problem(
                status: .unprocessableContent,
                detail: "package doesn't contain a valid manifest (Package.swift) file"
            )
        }
        try await self.manifestRepository.add(.init(packageId: id, version: version), manifests: manifests)
        // save release metadata
        guard try await self.packageRepository.add(packageRelease) else {
            throw Problem(
                status: .conflict,
                type: ProblemType.versionAlreadyExists.url,
                detail: "a release with version \(version) already exists"
            )
        }
        return .init(status: .created)
    }

    /// Extract manifests from zip file
    func extractManifestsFromZipFile(_ filename: String) async throws -> [ManifestVersion] {
        do {
            let zipFileManager = ZipFileManager()
            return try await zipFileManager.withZipFile(filename) { zip in
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
                var manifests: [ManifestVersion] = []
                for file in packageSwiftFiles {
                    let version: String?
                    if file.filename == "/package.swift" {
                        version = nil
                    } else if let v = file.filename.wholeMatch(of: packageSwiftRegex)?.output.1 {
                        version = String(v)
                    } else {
                        continue
                    }
                    let fileContents = try await zipFileManager.loadFile(zip, at: file.position)
                    manifests.append(.init(manifest: fileContents, swiftVersion: version))
                }
                return manifests
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
            OneOrMore(.digit)
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
