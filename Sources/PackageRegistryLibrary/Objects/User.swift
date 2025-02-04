import Foundation
import HummingbirdAuth

/// Basic user details
public struct User: Sendable {
    public init(id: UUID, username: String, passwordHash: String) {
        self.id = id
        self.username = username
        self.passwordHash = passwordHash
    }

    let id: UUID
    let username: String
    let passwordHash: String
}
