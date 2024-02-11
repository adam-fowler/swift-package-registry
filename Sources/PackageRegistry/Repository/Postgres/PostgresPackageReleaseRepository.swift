import Foundation
@_spi(ConnectionPool) import PostgresNIO

struct PostgresPackageReleaseRepository: PackageReleaseRepository {
    typealias Context = PostgresContext
    struct Error: Swift.Error {
        let message: String
    }

    let client: PostgresClient
    static var statusDataType: PostgresDataType!

    func withContext<Value>(logger: Logger, _ process: (Context) async throws -> Value) async throws -> Value {
        try await self.client.withConnection { connection in
            try await process(.init(connection: connection, logger: logger))
        }
    }

    func add(_ package: PackageRelease, context: Context) async throws -> Bool {
        let releaseID = package.releaseID.id
        _ = try await context.connection.query(
            "INSERT INTO PackageRelease VALUES (\(releaseID), \(package), \(package.id), 'ok')",
            logger: context.logger
        )
        if let repositoryURLs = package.metadata?.repositoryURLs {
            for url in repositoryURLs {
                _ = try await context.connection.query(
                    "INSERT INTO urls VALUES (\(url), \(package.id))",
                    logger: context.logger
                )
            }
        }
        return true
    }

    func get(id: PackageIdentifier, version: Version, context: Context) async throws -> PackageRelease? {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        let stream = try await context.connection.query(
            "SELECT release FROM PackageRelease WHERE id = \(releaseId.id)",
            logger: context.logger
        )
        return try await stream.decode(PackageRelease.self, context: .default).first { _ in true }
    }

    func list(id: PackageIdentifier, context: Context) async throws -> [ListRelease] {
        let stream = try await context.connection.query(
            "SELECT release, status FROM PackageRelease WHERE package_id = \(id.id)",
            logger: context.logger
        )
        var releases: [ListRelease] = []
        for try await (release, status) in stream.decode((PackageRelease, PackageStatus).self, context: .default) {
            releases.append(.init(id: id, version: release.version, status: status))
        }
        return releases
    }

    func setStatus(id: PackageIdentifier, version: Version, status: PackageStatus, context: Context) async throws {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        _ = try await context.connection.query(
            "UPDATE PackageRelease SET status = \(status) WHERE id = \(releaseId.id)",
            logger: context.logger
        )
    }

    func query(url: String, context: Context) async throws -> [PackageIdentifier] {
        let stream = try await context.connection.query(
            "SELECT package_id FROM urls WHERE url = \(url)",
            logger: context.logger
        )
        var packages: [PackageIdentifier] = []
        for try await (packageId) in stream.decode(PackageIdentifier.self, context: .default) {
            packages.append(packageId)
        }
        return packages
    }
}
