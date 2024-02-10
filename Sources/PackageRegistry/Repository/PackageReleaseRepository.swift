enum PackageStatus {
    case active
    case deleted
    case processing

    var problem: ListReleaseResponse.Release.Problem? {
        switch self {
        case .deleted:
            ListReleaseResponse.Release.Problem(status: .gone, detail: "this release was removed from the registry")
        case .active:
            nil
        case .processing:
            nil
        }
    }

    var shoudBeListed: Bool {
        switch self {
        case .active, .deleted:
            true
        case .processing:
            false
        }
    }
}

struct ListRelease {
    let id: PackageIdentifier
    let version: Version
    let status: PackageStatus
}

/// Package release repository
protocol PackageReleaseRepository {
    func add(_ release: PackageRelease) async throws -> Bool
    func get(id: PackageIdentifier, version: Version) async throws -> PackageRelease?
    func list(id: PackageIdentifier) async throws -> [ListRelease]
    func setStatus(id: PackageIdentifier, version: Version, status: PackageStatus)
    func query(url: String) async throws -> [PackageIdentifier]
}

struct PackageReleaseIdentifier: Hashable, Equatable {
    let packageId: PackageIdentifier
    let version: Version

    var id: String { self.packageId.description + self.version.description }
}

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
