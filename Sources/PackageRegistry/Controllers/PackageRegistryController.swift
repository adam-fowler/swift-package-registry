import Foundation
import HTTPTypes
import Hummingbird
import MultipartKit

extension HTTPField.Name {
    static var link: Self { .init("Link")! }
}

struct PackageRegistryController<RegistryStorage: Storage, Repository: PackageReleaseRepository> {
    typealias Context = RequestContext

    let storage: RegistryStorage
    let repository: Repository

    func addRoutes(to group: HBRouterGroup<Context>) {
        group.get("/{scope}/{name}", use: self.list)
        group.get("/{scope}/{name}/{version}.zip", use: self.download)
        group.get("/{scope}/{name}/{version}/Package.swift{swiftVersion}", use: self.getMetadataForSwiftVersion)
        group.get("/identifiers{url}", use: self.lookupIdentifiers)
        group.get("/{scope}/{name}/{version}", use: self.getMetadata)
        group.put("/{scope}/{name}/{version}", use: self.createRelease)
        group.on("**", method: .options, use: self.options)
    }

    @Sendable func options(_: HBRequest, context _: Context) async throws -> HBResponse {
        return .init(
            status: .ok,
            headers: [
                .allow: "GET, PUT",
                .link: "service-doc=https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md,service-desc=https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/registry.openapi.yaml",
            ]
        )
    }

    @Sendable func list(_: HBRequest, context: Context) async throws -> HBEditedResponse<ListReleaseResponse> {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let id = try PackageIdentifier(scope: scope, name: name)
        let releases = try await repository.list(id: id)
        let response = ListReleaseResponse(releases: releases.map {
            return .init(
                url: "https://localhost:8080/repository/\(scope)/\(name)/\($0.version)",
                problem: $0.status.problem
            )
        })
        var headers: HTTPFields = .init()
        if let latestRelease = releases.max(by: { $0.version < $1.version }) {
            headers[values: .link].append("<https://localhost:8080/repository/\(scope)/\(name)/\(latestRelease.version)>; rel=\"latest-version\"")
        }
        return .init(
            headers: headers,
            response: response
        )
    }

    @Sendable func getMetadata(_: HBRequest, context: Context) async throws -> HBEditedResponse<PackageRelease> {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let id = try PackageIdentifier(scope: scope, name: name)
        guard let release = try await repository.get(id: id, version: version) else {
            throw HBHTTPError(.notFound)
        }
        let releases = try await repository.list(id: id)
        let sortedReleases = releases.sorted { $0.version < $1.version }

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

    @Sendable func getMetadataForSwiftVersion(_: HBRequest, context _: Context) async throws -> HBResponse {
        .init(status: .notFound)
    }

    @Sendable func download(_: HBRequest, context: Context) async throws -> HBResponse {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let filename = "\(scope).\(name)/\(version).zip"
        let responseBody = try await self.storage.readFile(filename, context: context)
        return .init(
            status: .ok,
            headers: [
                .contentType: HBMediaType.applicationZip.description,
                .contentDisposition: "attachment; filename=\"\(name)-\(version).zip\"",
                .cacheControl: "public, immutable",
                // .digest
            ],
            body: responseBody
        )
    }

    @Sendable func lookupIdentifiers(_: HBRequest, context _: Context) async throws -> HBResponse {
        .init(status: .notFound)
    }

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
        let packageRelease = createRequest.createRelease(id: id, version: version)
        // save release metadata
        guard try await self.repository.add(packageRelease) else {
            throw Problem(
                status: .conflict,
                type: ProblemType.versionAlreadyExists.url,
                detail: "a release with version \(version) already exists"
            )
        }
        // save release zip
        let folder = "\(scope).\(name)"
        let filename = "\(scope).\(name)/\(version).zip"
        try await storage.makeDirectory(folder, context: context)
        try await self.storage.writeFile(filename, buffer: ByteBuffer(data: createRequest.sourceArchive), context: context)
        return .init(status: .created)
    }
}
