import Algorithms
import Foundation
import HummingbirdAuth
import HummingbirdBcrypt
import HummingbirdPostgres
import NIOPosix
import PostgresMigrations
import PostgresNIO

struct AddAdminUser: DatabaseMigration {
    func apply(connection: PostgresConnection, logger: Logger) async throws {
        let password = String("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomSample(count: 24))
        logger.critical("Admin password is \(password)")
        let passwordHash = try await NIOThreadPool.singleton.runIfActive { Bcrypt.hash(password, cost: 12) }
        try await connection.query(
            "INSERT INTO users VALUES (\(UUID()), 'admin', \(passwordHash))",
            logger: logger
        )
    }

    func revert(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query(
            "DELETE FROM users WHERE username = 'admin'",
            logger: logger
        )
    }
}
