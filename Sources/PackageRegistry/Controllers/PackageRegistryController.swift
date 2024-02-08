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
        group.get("/{scope}/{name}/{version}", use: self.getMetadata)
        group.get("/{scope}/{name}/{version}/Package.swift{swiftVersion}", use: self.getMetadataForSwiftVersion)
        group.get("/{scope}/{name}/{version}.zip", use: self.download)
        group.get("/identifiers{url}", use: self.lookupIdentifiers)
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

    @Sendable func list(_: HBRequest, context: Context) async throws -> ListReleaseResponse {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let id = try PackageIdentifier(scope: scope, name: name)
        let releases = try await repository.list(id: id)
        return .init(releases: releases.map {
            return .init(
                url: "https://localhost:8080/repository/\(scope)/\(name)/\($0.version)", 
                problem: $0.status.problem
            )
        })
    }

    @Sendable func getMetadata(_: HBRequest, context: Context) async throws -> PackageRelease {
        let scope = try context.parameters.require("scope")
        let name = try context.parameters.require("name")
        let version = try context.parameters.require("version", as: Version.self)
        let id = try PackageIdentifier(scope: scope, name: name)
        guard let release = try await repository.get(id: id, version: version) else {
            throw HBHTTPError(.notFound)
        }
        return release
    }

    @Sendable func getMetadataForSwiftVersion(_: HBRequest, context _: Context) async throws -> HBResponse {
        .init(status: .notFound)
    }

    @Sendable func download(_: HBRequest, context _: Context) async throws -> HBResponse {

        .init(status: .notFound)
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
        let filename = "\(scope).\(name)/\(version)"
        try await storage.makeDirectory(folder, context: context)
        try await self.storage.writeFile(filename, buffer: ByteBuffer(data: createRequest.sourceArchive), context: context)
        return .init(status: .created)
    }
}
