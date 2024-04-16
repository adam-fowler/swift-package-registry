import PostgresNIO

enum PackageStatus: String {
    case ok
    case deleted
    case processing

    var problem: ListReleaseResponse.Release.Problem? {
        switch self {
        case .deleted:
            ListReleaseResponse.Release.Problem(status: .gone, detail: "this release was removed from the registry")
        case .ok:
            nil
        case .processing:
            nil
        }
    }

    var shoudBeListed: Bool {
        switch self {
        case .ok, .deleted:
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
    func add(_ release: PackageRelease, logger: Logger) async throws -> Bool
    func get(id: PackageIdentifier, version: Version, logger: Logger) async throws -> PackageRelease?
    func list(id: PackageIdentifier, logger: Logger) async throws -> [ListRelease]
    func setStatus(id: PackageIdentifier, version: Version, status: PackageStatus, logger: Logger) async throws
    func query(url: String, logger: Logger) async throws -> [PackageIdentifier]
}
