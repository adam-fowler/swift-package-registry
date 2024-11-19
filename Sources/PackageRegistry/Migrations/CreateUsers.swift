import HummingbirdPostgres
import PostgresMigrations
import PostgresNIO

struct CreateUsers: DatabaseMigration {
    func apply(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query(
            """
            CREATE TABLE users (
                "id" uuid PRIMARY KEY,
                "username" text,
                "password_hash" text
            )
            """,
            logger: logger
        )
    }

    func revert(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query(
            "DROP TABLE users",
            logger: logger
        )
    }
}
