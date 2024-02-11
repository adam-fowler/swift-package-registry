import Hummingbird

struct ProblemMiddleware<Context: HBBaseRequestContext>: HBMiddlewareProtocol {
    func handle(_ request: HBRequest, context: Context, next: (HBRequest, Context) async throws -> HBResponse) async throws -> HBResponse {
        do {
            return try await next(request, context)
        } catch let error as Problem {
            throw error
        } catch let error as HBHTTPError {
            throw error
        } catch {
            throw Problem(
                status: .internalServerError,
                detail: String(reflecting: error)
            )
        }
    }
}
