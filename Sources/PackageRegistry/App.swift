import ArgumentParser
import Hummingbird

@main
struct App: AsyncParsableCommand, AppArguments {
    @Option(name: .shortAndLong)
    var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong)
    var port: Int = 8080

    @Flag(name: .shortAndLong)
    var inMemory: Bool = false

    @Flag(name: .shortAndLong)
    var revert: Bool = false

    @Flag(name: .shortAndLong)
    var migrate: Bool = false

    func run() async throws {
        let app = try await buildApplication(self)
        try await app.runService()
    }
}
