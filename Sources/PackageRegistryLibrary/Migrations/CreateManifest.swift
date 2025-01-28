import PostgresNIO
import HummingbirdPostgres
import PostgresMigrations

struct CreateManifest: DatabaseMigration {
    func apply(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query(
            """
            CREATE TABLE manifests (
                "release_id" text PRIMARY KEY,
                "default_manifest" text,
                "manifest_versions" text[],
                "swift_versions" text[]
            )
            """,
            logger: logger
        )
    }

    func revert(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query(
            "DROP TABLE manifests",
            logger: logger
        )
    }
}
