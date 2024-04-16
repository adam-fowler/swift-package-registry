import Logging
import NIOCore

struct Manifests {
    struct Version {
        let manifest: ByteBuffer
        let swiftVersion: String
    }

    let `default`: ByteBuffer
    let versions: [Version]
}

/// Manifest repository
protocol ManifestRepository {
    func add(_ id: PackageReleaseIdentifier, manifests: Manifests, logger: Logger) async throws
    func get(_ id: PackageReleaseIdentifier, logger: Logger) async throws -> Manifests?
}
