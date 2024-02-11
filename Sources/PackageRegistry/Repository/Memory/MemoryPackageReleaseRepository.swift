/// Memory implementation of package release repository
final class MemoryPackageReleaseRepository: PackageReleaseRepository {
    struct PackageReleaseStorage {
        let release: PackageRelease
        var status: PackageStatus
    }

    var packages: [String: PackageReleaseStorage]

    init() {
        self.packages = .init()
    }

    func add(_ release: PackageRelease) throws -> Bool {
        let releaseId = PackageReleaseIdentifier(packageId: release.id, version: release.version)
        if self.packages[releaseId.id] != nil {
            return false
        }
        self.packages[releaseId.id] = PackageReleaseStorage(release: release, status: .active)
        return true
    }

    func get(id: PackageIdentifier, version: Version) throws -> PackageRelease? {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        return self.packages[releaseId.id]?.release
    }

    func list(id: PackageIdentifier) throws -> [ListRelease] {
        var releases = [ListRelease].init()
        for release in self.packages.values {
            if release.release.id == id {
                releases.append(.init(id: id, version: release.release.version, status: release.status))
            }
        }
        return releases
    }

    func setStatus(id: PackageIdentifier, version: Version, status: PackageStatus) {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        self.packages[releaseId.id]?.status = status
    }

    func query(url: String) async throws -> [PackageIdentifier] {
        var identifierSet = Set<PackageIdentifier>()
        for package in self.packages.values {
            if package.release.metadata?.repositoryURLs?.first(where: { $0 == url }) != nil {
                identifierSet.insert(package.release.id)
            }
        }
        return .init(identifierSet)
    }
}
