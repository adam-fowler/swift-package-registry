import Logging

/// Protocol for a migration repository
protocol MigrationRepository {
    associatedtype Context
    func withContext(logger: Logger, _ process: (Context) async throws -> Void) async throws
    func add(_ migration: Migration, context: Context) async throws
    func remove(_ migration: Migration, context: Context) async throws
    func getAll(context: Context) async throws -> [String]
}
