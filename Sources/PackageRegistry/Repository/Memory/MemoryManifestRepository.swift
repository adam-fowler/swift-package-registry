import NIOCore

/// Manifest repository
protocol ManifestRepository {
    func add(_ id: PackageReleaseIdentifier, manifests: [ManifestVersion]) async throws
    func get(_ id: PackageReleaseIdentifier) async throws -> [ManifestVersion]?
}

class MemoryManifestRepository: ManifestRepository {
    init() {
        self.manifests = .init()
    }

    func add(_ id: PackageReleaseIdentifier, manifests: [ManifestVersion]) async throws {
        self.manifests[id] = manifests
    }

    func get(_ id: PackageReleaseIdentifier) async throws -> [ManifestVersion]? {
        return self.manifests[id]
    }

    var manifests: [PackageReleaseIdentifier: [ManifestVersion]]
}
