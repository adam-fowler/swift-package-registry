@_spi(ConnectionPool) import PostgresNIO

struct CreateURLPackageReference: Migration {
    func migrate(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query(
            """
            CREATE TABLE urls (
                "url" text,
                "package_id" text
            )
            """,
            logger: logger
        )
    }

    func revert(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query(
            "DROP TABLE urls",
            logger: logger
        )
    }
}
