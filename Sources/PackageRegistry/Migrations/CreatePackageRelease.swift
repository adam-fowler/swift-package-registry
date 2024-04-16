import HummingbirdPostgres
import PostgresNIO

struct CreatePackageRelease: PostgresMigration {
    func apply(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query(
            "CREATE TYPE status AS ENUM ('processing', 'ok', 'deleted')",
            logger: logger
        )
        try await connection.query(
            """
            CREATE TABLE PackageRelease (
                "id" text PRIMARY KEY,
                "release" jsonb,
                "package_id" text,
                "status" status 
            )
            """,
            logger: logger
        )
    }

    func revert(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query(
            "DROP TABLE PackageRelease",
            logger: logger
        )
        try await connection.query(
            "DROP TYPE status",
            logger: logger
        )
    }
}
