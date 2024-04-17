import Foundation
import HummingbirdAuth

/// Basic user details
struct User: Authenticatable {
    let id: UUID
    let username: String
    let passwordHash: String
}
