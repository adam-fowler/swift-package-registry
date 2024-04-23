import Foundation
import PostgresNIO

struct PostgresPackageReleaseRepository: PackageReleaseRepository {
    struct Error: Swift.Error {
        let message: String
    }

    let client: PostgresClient
    static var statusDataType: PostgresDataType!

    func add(_ package: PackageRelease, logger: Logger) async throws -> Bool {
        let releaseID = package.releaseID.id
        do {
            _ = try await self.client.query(
                "INSERT INTO PackageRelease VALUES (\(releaseID), \(package), \(package.id), 'ok')",
                logger: logger
            )
        } catch let error as PSQLError {
            if error.serverError == .uniqueViolation {
                return false
            } else {
                throw error
            }
        }
        if let repositoryURLs = package.metadata?.repositoryURLs {
            for url in repositoryURLs {
                _ = try await self.client.query(
                    "INSERT INTO urls VALUES (\(url), \(package.id))",
                    logger: logger
                )
            }
        }
        return true
    }

    func get(id: PackageIdentifier, version: Version, logger: Logger) async throws -> PackageRelease? {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        let stream = try await client.query(
            "SELECT release FROM PackageRelease WHERE id = \(releaseId.id)",
            logger: logger
        )
        return try await stream.decode(PackageRelease.self, context: .default).first { _ in true }
    }

    func list(id: PackageIdentifier, logger: Logger) async throws -> [ListRelease] {
        let stream = try await client.query(
            "SELECT release, status FROM PackageRelease WHERE package_id = \(id.id)",
            logger: logger
        )
        var releases: [ListRelease] = []
        for try await (release, status) in stream.decode((PackageRelease, PackageStatus).self, context: .default) {
            releases.append(.init(id: id, version: release.version, status: status))
        }
        return releases
    }

    func setStatus(id: PackageIdentifier, version: Version, status: PackageStatus, logger: Logger) async throws {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        _ = try await self.client.query(
            "UPDATE PackageRelease SET status = \(status) WHERE id = \(releaseId.id)",
            logger: logger
        )
    }

    func query(url: String, logger: Logger) async throws -> [PackageIdentifier] {
        let stream = try await client.query(
            "SELECT package_id FROM urls WHERE url = \(url)",
            logger: logger
        )
        var packages: [PackageIdentifier] = []
        for try await (packageId) in stream.decode(PackageIdentifier.self, context: .default) {
            packages.append(packageId)
        }
        return packages
    }
}
