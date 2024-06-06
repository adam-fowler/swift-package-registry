import Hummingbird

extension PackageRegistryRequestContext {
    @TaskLocal static var context: Self?
}
/// Save context in task locals for use by OpenAPI
struct TaskLocalContextMiddleware: RouterMiddleware {
    typealias Context = PackageRegistryRequestContext

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        try await Context.$context.withValue(context) {
            return try await next(request, context)
        }
    }
}
