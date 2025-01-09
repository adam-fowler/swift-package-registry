import Hummingbird
import StructuredFieldValues

struct OptionsMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        if request.method == .options {
            let linkHeader = LinkHeader(items: [
                .init(
                    item: "<https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md>",
                    parameters: ["rel": "service-doc"]
                ),
                .init(
                    item: "<https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/registry.openapi.yaml>",
                    parameters: ["rel": "service-desc"]
                ),
            ])
            return try .init(
                status: .ok,
                headers: [
                    .allow: "GET, PUT",
                    .link: StructuredFieldValueEncoder().encodeAsString(linkHeader),
                ]
            )
        }
        return try await next(request, context)
    }
}
