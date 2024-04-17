import Foundation
import Logging
import NIOCore

/// User repository
protocol UserRepository: Sendable {
    func add(user: User, logger: Logger) async throws
    func get(username: String, logger: Logger) async throws -> User?
    func get(id: UUID, logger: Logger) async throws -> User?
}
