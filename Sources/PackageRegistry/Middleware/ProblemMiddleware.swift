import Hummingbird

struct ProblemMiddleware<Context: BaseRequestContext>: RouterMiddleware {
    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as Problem {
            throw error
        } catch let error as HTTPError {
            throw error
        } catch {
            throw Problem(
                status: .internalServerError,
                detail: String(reflecting: error)
            )
        }
    }
}
