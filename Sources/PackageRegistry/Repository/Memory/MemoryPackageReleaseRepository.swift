import Logging

/// Memory implementation of package release repository
final class MemoryPackageReleaseRepository: PackageReleaseRepository {
    struct PackageReleaseStorage {
        let release: PackageRelease
        var status: PackageStatus
    }

    typealias Context = Void

    var packages: [String: PackageReleaseStorage]

    init() {
        self.packages = .init()
    }

    func withContext<Value>(logger: Logger, _ process: (Context) async throws -> Value) async throws -> Value {
        try await process(())
    }

    func add(_ release: PackageRelease, context: Context) throws -> Bool {
        let releaseID = release.releaseID
        if self.packages[releaseID.id] != nil {
            return false
        }
        self.packages[releaseID.id] = PackageReleaseStorage(release: release, status: .ok)
        return true
    }

    func get(id: PackageIdentifier, version: Version, context: Context) throws -> PackageRelease? {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        return self.packages[releaseId.id]?.release
    }

    func list(id: PackageIdentifier, context: Context) throws -> [ListRelease] {
        var releases = [ListRelease].init()
        for release in self.packages.values {
            if release.release.id == id {
                releases.append(.init(id: id, version: release.release.version, status: release.status))
            }
        }
        return releases
    }

    func setStatus(id: PackageIdentifier, version: Version, status: PackageStatus, context: Context) {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        self.packages[releaseId.id]?.status = status
    }

    func query(url: String, context: Context) async throws -> [PackageIdentifier] {
        var identifierSet = Set<PackageIdentifier>()
        for package in self.packages.values {
            if package.release.metadata?.repositoryURLs?.first(where: { $0 == url }) != nil {
                identifierSet.insert(package.release.id)
            }
        }
        return .init(identifierSet)
    }
}
