import Foundation
import PostgresNIO

public struct PostgresUserRepository: UserRepository {
    let client: PostgresClient

    public init(client: PostgresClient) {
        self.client = client
    }
    
    public func add(user: User, logger: Logger) async throws {
        _ = try await self.client.query(
            "INSERT INTO users VALUES (\(user.id), \(user.username), \(user.passwordHash))",
            logger: logger
        )
    }

    public func get(username: String, logger: Logger) async throws -> User? {
        let stream = try await client.query(
            "SELECT id, password_hash FROM users WHERE username = \(username)",
            logger: logger
        )
        for try await (id, passwordHash) in stream.decode((UUID, String).self, context: .default) {
            return .init(id: id, username: username, passwordHash: passwordHash)
        }
        return nil
    }

    public func get(id: UUID, logger: Logger) async throws -> User? {
        let stream = try await client.query(
            "SELECT username, password_hash FROM users WHERE id = \(id)",
            logger: logger
        )
        for try await (username, passwordHash) in stream.decode((String, String).self, context: .default) {
            return .init(id: id, username: username, passwordHash: passwordHash)
        }
        return nil
    }
}
