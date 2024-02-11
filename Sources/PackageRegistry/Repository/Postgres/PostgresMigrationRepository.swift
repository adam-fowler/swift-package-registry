import Logging
@_spi(ConnectionPool) import PostgresNIO

struct PostgresMigrationRepository: MigrationRepository {
    typealias Context = PostgresContext

    let client: PostgresClient

    func withContext(logger: Logger, _ process: (Context) async throws -> Void) async throws {
        _ = try await self.client.withConnection { connection in
            try await self.createMigrationsTable(connection: connection, logger: logger)
            try await process(.init(connection: connection, logger: logger))
        }
    }

    func add(_ migration: Migration, context: Context) async throws {
        try await migration.migrate(connection: context.connection, logger: context.logger)
        try await context.connection.query(
            "INSERT INTO _migrations_ (name) VALUES (\(migration.name))",
            logger: context.logger
        )
    }

    func remove(_ migration: Migration, context: Context) async throws {
        try await migration.revert(connection: context.connection, logger: context.logger)
        try await context.connection.query(
            "DELETE FROM _migrations_ WHERE name = \(migration.name)",
            logger: context.logger
        )
    }

    func getAll(context: Context) async throws -> [String] {
        let stream = try await context.connection.query(
            "SELECT name FROM _migrations_ ORDER BY \"order\"",
            logger: context.logger
        )
        var result: [String] = []
        for try await name in stream.decode(String.self, context: .default) {
            result.append(name)
        }
        return result
    }

    private func createMigrationsTable(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query(
            """
            CREATE TABLE IF NOT EXISTS _migrations_ (
                "order" SERIAL PRIMARY KEY,
                "name" text 
            )
            """,
            logger: logger
        )
    }
}
