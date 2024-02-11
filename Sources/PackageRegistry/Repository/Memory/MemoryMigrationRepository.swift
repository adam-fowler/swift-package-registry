import Logging

class MemoryMigrationRepository: MigrationRepository {
    init() {
        self.migrations = .init()
    }

    typealias Context = Void

    func withContext(logger: Logger, _ process: (Context) async throws -> Void) async throws {
        try await process(())
    }

    func add(_ migration: Migration, context: Context) {
        self.migrations.append(migration)
    }

    func remove(_ migration: Migration, context: Context) {
        self.migrations.removeAll { $0.name == migration.name }
    }

    func getAll(context: Context) -> [String] {
        return self.migrations.map(\.name)
    }

    var migrations: [Migration]
}
