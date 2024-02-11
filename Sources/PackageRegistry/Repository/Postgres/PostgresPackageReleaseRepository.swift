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
            "INSERT INTO PackageRelease VALUES (\(releaseID), \(package), \(package.id.id), 'ok')",
            logger: context.logger
        )
        if let repositoryURLs = package.metadata?.repositoryURLs {
            for url in repositoryURLs {
                _ = try await context.connection.query(
                    "INSERT INTO urls VALUES (\(url), \(package.id.id))",
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
        for try await (packageId) in stream.decode(String.self, context: .default) {
            try packages.append(.init(packageId))
        }
        return packages
    }
}

extension PackageRelease: PostgresEncodable, PostgresDecodable {
    /// The data type encoded into the `byteBuffer` in ``encode(into:context:)``.
    static var psqlType: PostgresDataType { .jsonb }

    /// The Postgres encoding format used to encode the value into `byteBuffer` in ``encode(into:context:)``.
    static var psqlFormat: PostgresFormat { .binary }
}

extension PackageStatus: PostgresDecodable, PostgresEncodable {
    static var psqlType: PostgresDataType = .null
    static var psqlFormat: PostgresFormat { .text }

    static func setDataType(client: PostgresClient, logger: Logger) async throws {
        guard let statusDataType: PostgresDataType = try await client.withConnection({ connection -> PostgresDataType? in
            let stream = try await connection.query(
                "SELECT oid FROM pg_type WHERE typname = 'status';",
                logger: logger
            )
            return try await stream.decode(UInt32.self, context: .default)
                .first { _ in true }
                .map { oid in PostgresDataType(numericCast(oid)) }
        }) else {
            throw PostgresError(message: "Failed to get status type")
        }
        Self.psqlType = statusDataType
    }

    func encode(
        into byteBuffer: inout ByteBuffer,
        context: PostgresEncodingContext<some PostgresNIO.PostgresJSONEncoder>
    ) throws {
        byteBuffer.writeString(self.rawValue)
    }

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

extension UInt32: PostgresDecodable {
    @inlinable
    public init(
        from buffer: inout ByteBuffer,
        type: PostgresDataType,
        format: PostgresFormat,
        context: PostgresDecodingContext<some PostgresJSONDecoder>
    ) throws {
        switch (format, type) {
        case (.binary, .oid):
            guard buffer.readableBytes == 4, let value = buffer.readInteger(as: UInt32.self) else {
                throw PostgresDecodingError.Code.failure
            }
            self = UInt32(value)
        default:
            throw PostgresDecodingError.Code.typeMismatch
        }
    }
}
