import Logging
import NIOCore

class MemoryManifestRepository: ManifestRepository {
    init() {
        self.manifests = .init()
    }

    func add(_ id: PackageReleaseIdentifier, manifests: Manifests, logger: Logger) async throws {
        self.manifests[id] = manifests
    }

    func get(_ id: PackageReleaseIdentifier, logger: Logger) async throws -> Manifests? {
        return self.manifests[id]
    }

    var manifests: [PackageReleaseIdentifier: Manifests]
}
