import Logging
import NIOCore

public struct Manifests: Sendable {
    struct Version {
        let manifest: ByteBuffer
        let swiftVersion: String
    }

    let `default`: ByteBuffer
    let versions: [Version]
}

/// Manifest repository
public protocol ManifestRepository: Sendable {
    func add(_ id: PackageReleaseIdentifier, manifests: Manifests, logger: Logger) async throws
    func get(_ id: PackageReleaseIdentifier, logger: Logger) async throws -> Manifests?
}
