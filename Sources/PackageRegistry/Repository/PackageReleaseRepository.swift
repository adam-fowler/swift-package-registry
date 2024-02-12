@_spi(ConnectionPool) import PostgresNIO

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
    associatedtype Context

    func withContext<Value>(logger: Logger, _ process: (Context) async throws -> Value) async throws -> Value

    func add(_ release: PackageRelease, context: Context) async throws -> Bool
    func get(id: PackageIdentifier, version: Version, context: Context) async throws -> PackageRelease?
    func list(id: PackageIdentifier, context: Context) async throws -> [ListRelease]
    func setStatus(id: PackageIdentifier, version: Version, status: PackageStatus, context: Context) async throws
    func query(url: String, context: Context) async throws -> [PackageIdentifier]
}
