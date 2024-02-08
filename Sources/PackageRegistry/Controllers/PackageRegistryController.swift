import HTTPTypes
import Hummingbird

extension HTTPField.Name {
    static var link: Self { .init("Link")! }
}

struct PackageRegistryController<RegistryStorage: Storage> {
    typealias Context = RequestContext

    let storage: RegistryStorage

    func addRoutes(to group: HBRouterGroup<Context>) {
        group.get("/{scope}/{name}", use: list)
        group.get("/{scope}/{name}/{version}", use: getMetadata)
        group.get("/{scope}/{name}/{version}/Package.swift{swiftVersion}", use: getMetadataForSwiftVersion)
        group.get("/{scope}/{name}/{version}.zip", use: download)
        group.get("/identifiers{url}", use: lookupIdentifiers)
        group.put("/{scope}/{name}/{version}", use: createRelease)
        group.on("**", method: .options, use: options)
    }

    @Sendable func options(_ request: HBRequest, context: Context) async throws -> HBResponse {
        return .init(
            status: .ok,
            headers: [
                .allow: "GET, PUT",
                .link: "service-doc=https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md,service-desc=https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/registry.openapi.yaml"
            ]
        )
    }

    @Sendable func list(_ request: HBRequest, context: Context) async throws -> HBResponse {
        .init(status: .notFound)
    }

    @Sendable func getMetadata(_ request: HBRequest, context: Context) async throws -> HBResponse {
        .init(status: .notFound)
    }

    @Sendable func getMetadataForSwiftVersion(_ request: HBRequest, context: Context) async throws -> HBResponse {
        .init(status: .notFound)
    }

    @Sendable func download(_ request: HBRequest, context: Context) async throws -> HBResponse {
        .init(status: .notFound)
    }

    @Sendable func lookupIdentifiers(_ request: HBRequest, context: Context) async throws -> HBResponse {
        .init(status: .notFound)
    }

    @Sendable func createRelease(_ request: HBRequest, context: Context) async throws -> HBResponse {
        guard let contentType = request.headers[.contentType],
            let mediaType = HBMediaType(from: contentType) else { throw HBHTTPError(.badRequest)}
        guard case .multipartForm = mediaType else { throw HBHTTPError(.badRequest)}


        return .init(status: .notFound)
    }
}