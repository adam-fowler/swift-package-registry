import HTTPTypes
import Hummingbird

extension HTTPField.Name {
    static var link: Self { .init("Link")! }
}

struct PacakageRegistryController {
    typealias Context = RequestContext
    func addRoutes(to router: HBRouter<Context>) {
        router.get("/{scope}/{name}", use: list)
        router.get("/{scope}/{name}/{version}", use: getMetadata)
        router.get("/{scope}/{name}/{version}/Package.swift{swiftVersion}", use: getMetadataForSwiftVersion)
        router.get("/{scope}/{name}/{version}.zip", use: download)
        router.get("/identifiers{url}", use: lookupIdentifiers)
        router.put("/{scope}/{name}/{version}", use: createRelease)
        router.on("**", method: .options, use: options)
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
        .init(status: .notFound)
    }
}