import Logging
@_spi(ConnectionPool) import PostgresNIO

protocol Migration {
    func migrate(connection: PostgresConnection, logger: Logger) async throws
    func revert(connection: PostgresConnection, logger: Logger) async throws
}

extension Migration {
    var name: String { String(describing: Self.self) }
}

struct MigrationError: Error {
    let message: String
}

final class Migrations<Repository: MigrationRepository> {
    let repository: Repository
    var migrations: [Migration]
    var reverts: [String: Migration]

    init(repository: Repository) {
        self.repository = repository
        self.migrations = []
        self.reverts = [:]
    }

    @MainActor
    func add(_ migration: Migration) {
        self.migrations.append(migration)
    }

    /// Add migration to list of reverts, that can be applied
    @MainActor
    func add(revert migration: Migration) {
        self.reverts[migration.name] = migration
    }

    @MainActor
    func migrate(logger: Logger, dryRun: Bool) async throws {
        try await self.migrate(migrations: self.migrations, logger: logger, dryRun: dryRun)
    }

    @MainActor
    func revert(logger: Logger, dryRun: Bool) async throws {
        try await self.migrate(migrations: [], logger: logger, dryRun: dryRun)
    }

    @MainActor
    private func migrate(migrations: [Migration], logger: Logger, dryRun: Bool) async throws {
        // try await self.createMigrationsTable(logger: logger)
        _ = try await self.repository.withContext(logger: logger) { context in
            let storedMigrations = try await self.repository.getAll(context: context)
            let minMigrationCount = min(migrations.count, storedMigrations.count)
            var i = 0
            while i < minMigrationCount, storedMigrations[i] == migrations[i].name {
                i += 1
            }
            // Revert deleted migrations, and any migrations after a deleted migration
            for j in (i..<storedMigrations.count).reversed() {
                let migrationName = storedMigrations[j]
                // look for migration to revert in migration list and revert dictionary
                guard let migration = self.migrations.first(where: { $0.name == migrationName }) ?? self.reverts[migrationName] else {
                    throw MigrationError(message: "Cannot find migration \(migrationName) to revert it.")
                }
                logger.info("Reverting \(migration.name)\(dryRun ? " (dry run)" : "")")
                if !dryRun {
                    try await self.repository.remove(migration, context: context)
                }
            }
            // Apply migration
            for j in i..<migrations.count {
                let migration = migrations[j]
                logger.info("Migrating \(migration.name)\(dryRun ? " (dry run)" : "")")
                if !dryRun {
                    try await self.repository.add(migration, context: context)
                }
            }
        }
    }
}
