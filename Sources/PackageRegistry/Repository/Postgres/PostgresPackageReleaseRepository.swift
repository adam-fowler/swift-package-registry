import Foundation
@_spi(ConnectionPool) import PostgresNIO

struct PostgresPackageReleaseRepository: PackageReleaseRepository {
    typealias Context = PostgresContext
    let client: PostgresClient

    func withContext<Value>(logger: Logger, _ process: (Context) async throws -> Value) async throws -> Value {
        try await self.client.withConnection { connection in
            try await process(.init(connection: connection, logger: logger))
        }
    }

    func add(_ package: PackageRelease, context: Context) async throws -> Bool {
        let releaseID = package.releaseID.id
        _ = try await context.connection.query(
            "INSERT INTO PackageRelease VALUES (\(releaseID), \(package), \(package.id.id), 'ok')",
            logger: context.logger
        )
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
            // guard let status = PackageStatus(rawValue: status) else { continue }
            releases.append(.init(id: id, version: release.version, status: status))
        }
        return releases
    }

    func setStatus(id: PackageIdentifier, version: Version, status: PackageStatus, context: Context) {}

    func query(url: String, context: Context) async throws -> [PackageIdentifier] {
        return []
    }
}

extension PackageRelease: PostgresEncodable, PostgresDecodable {
    /// The data type encoded into the `byteBuffer` in ``encode(into:context:)``.
    static var psqlType: PostgresDataType { .jsonb }

    /// The Postgres encoding format used to encode the value into `byteBuffer` in ``encode(into:context:)``.
    static var psqlFormat: PostgresFormat { .binary }
}

extension PackageStatus: PostgresDecodable {
    init(
        from byteBuffer: inout ByteBuffer,
        type: PostgresDataType,
        format: PostgresFormat,
        context: PostgresDecodingContext<some PostgresJSONDecoder>
    ) throws {
        let string = String(buffer: byteBuffer)
        guard let value = PackageStatus(rawValue: string) else {
            throw DecodingError.typeMismatch(Self.self, .init(codingPath: [], debugDescription: "Unexpected value: \(string)"))
        }
        self = value
    }
}
