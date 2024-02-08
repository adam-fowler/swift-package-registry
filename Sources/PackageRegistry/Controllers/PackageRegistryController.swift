import Foundation
import HTTPTypes
import Hummingbird
import MultipartKit

extension HTTPField.Name {
    static var link: Self { .init("Link")! }
}

struct PackageRegistryController<RegistryStorage: Storage> {
    typealias Context = RequestContext

    let storage: RegistryStorage

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

    @Sendable func list(_: HBRequest, context _: Context) async throws -> HBResponse {
        .init(status: .notFound)
    }

    @Sendable func getMetadata(_: HBRequest, context _: Context) async throws -> HBResponse {
        .init(status: .notFound)
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

    struct Release: Codable {
        let sourceArchive: Data
        let sourceArchiveSignature: Data?
        let metadata: String?
        let metadataSignature: Data?

        private enum CodingKeys: String, CodingKey {
            case sourceArchive = "source-archive"
            case sourceArchiveSignature = "source-archive-signature"
            case metadata
            case metadataSignature = "metadata-signature"
        }
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
        let version = try context.parameters.require("version")
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
        let release = try FormDataDecoder().decode(Release.self, from: body, boundary: parameter.value)
        let id = try PackageIdentifier(scope: scope, name: name)
        let folder = "\(scope).\(name)"
        let filename = "\(scope).\(name)/\(version)"
        try await storage.makeDirectory(folder, context: context)
        try await self.storage.writeFile(filename, buffer: ByteBuffer(data: release.sourceArchive), context: context)
        return .init(status: .created)
    }
}
