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
