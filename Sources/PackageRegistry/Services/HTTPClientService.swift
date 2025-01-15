import AsyncHTTPClient
import ServiceLifecycle

struct HTTPClientService: Service {
    let client: HTTPClient

    func run() async throws {
        try? await gracefulShutdown()
        try await client.shutdown()
    }
}
