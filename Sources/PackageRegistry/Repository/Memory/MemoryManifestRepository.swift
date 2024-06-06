import Logging
import NIOCore
import NIOConcurrencyHelpers

final class MemoryManifestRepository: ManifestRepository {
    init() {
        self.manifests = .init(.init())
    }

    func add(_ id: PackageReleaseIdentifier, manifests: Manifests, logger: Logger) async throws {
        self.manifests.withLockedValue { $0[id] = manifests }
    }

    func get(_ id: PackageReleaseIdentifier, logger: Logger) async throws -> Manifests? {
        return self.manifests.withLockedValue { $0[id] }
    }

    let manifests: NIOLockedValueBox<[PackageReleaseIdentifier: Manifests]>
}
