import ArgumentParser
import Hummingbird

@main
struct App: AsyncParsableCommand, AppArguments {
    @Option(name: .shortAndLong)
    var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong)
    var port: Int = 8081

    @Flag(name: .shortAndLong)
    var inMemory: Bool = false

    func run() async throws {
        let app = try await buildApplication(self)
        try await app.runService()
    }
}
