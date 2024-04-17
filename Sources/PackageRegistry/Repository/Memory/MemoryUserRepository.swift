import Foundation
import Logging

actor MemoryUserRepository: UserRepository {
    init() {
        self.users = .init()
    }

    func add(user: User, logger: Logging.Logger) async throws {
        self.users[user.id] = user
    }

    func get(username: String, logger: Logging.Logger) async throws -> User? {
        return self.users.values.first { $0.username == username }
    }

    func get(id: UUID, logger: Logging.Logger) async throws -> User? {
        return self.users[id]
    }

    var users: [UUID: User]
}
