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
    associatedtype Context

    func withContext<Value>(logger: Logger, _ process: (Context) async throws -> Value) async throws -> Value

    func add(_ id: PackageReleaseIdentifier, manifests: Manifests, context: Context) async throws
    func get(_ id: PackageReleaseIdentifier, context: Context) async throws -> Manifests?
}
