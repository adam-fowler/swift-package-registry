import Foundation
import Logging

public actor MemoryUserRepository: UserRepository {
    public init() {
        self.users = .init()
    }

    public func add(user: User, logger: Logging.Logger) async throws {
        self.users[user.id] = user
    }

    public func get(username: String, logger: Logging.Logger) async throws -> User? {
        self.users.values.first { $0.username == username }
    }

    public func get(id: UUID, logger: Logging.Logger) async throws -> User? {
        self.users[id]
    }

    var users: [UUID: User]
}
