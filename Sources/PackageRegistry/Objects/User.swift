import Foundation
import HummingbirdAuth

/// Basic user details
struct User: Sendable {
    let id: UUID
    let username: String
    let passwordHash: String
}
