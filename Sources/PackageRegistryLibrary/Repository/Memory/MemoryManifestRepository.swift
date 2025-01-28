import Logging
import NIOConcurrencyHelpers
import NIOCore

public final class MemoryManifestRepository: ManifestRepository {
    public init() {
        self.manifests = .init(.init())
    }

    public func add(_ id: PackageReleaseIdentifier, manifests: Manifests, logger: Logger) async throws {
        self.manifests.withLockedValue { $0[id] = manifests }
    }

    public func get(_ id: PackageReleaseIdentifier, logger: Logger) async throws -> Manifests? {
        self.manifests.withLockedValue { $0[id] }
    }

    let manifests: NIOLockedValueBox<[PackageReleaseIdentifier: Manifests]>
}
