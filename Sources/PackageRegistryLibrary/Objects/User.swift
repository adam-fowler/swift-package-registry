import Foundation
import HummingbirdAuth

/// Basic user details
public struct User: Sendable {
    let id: UUID
    let username: String
    let passwordHash: String
}
