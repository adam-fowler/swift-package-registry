import Logging
import NIOCore

class MemoryManifestRepository: ManifestRepository {
    init() {
        self.manifests = .init()
    }

    typealias Context = Void

    func withContext<Value>(logger: Logger, _ process: (Context) async throws -> Value) async throws -> Value {
        try await process(())
    }

    func add(_ id: PackageReleaseIdentifier, manifests: Manifests, context: Context) async throws {
        self.manifests[id] = manifests
    }

    func get(_ id: PackageReleaseIdentifier, context: Context) async throws -> Manifests? {
        return self.manifests[id]
    }

    var manifests: [PackageReleaseIdentifier: Manifests]
}
