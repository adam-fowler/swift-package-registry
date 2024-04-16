import PostgresNIO

extension PackageRelease: PostgresCodable {
    /// The data type encoded into the `byteBuffer` in ``encode(into:context:)``.
    static var psqlType: PostgresDataType { .jsonb }

    /// The Postgres encoding format used to encode the value into `byteBuffer` in ``encode(into:context:)``.
    static var psqlFormat: PostgresFormat { .binary }
}

extension PackageIdentifier: PostgresCodable {
    static var psqlType: PostgresDataType = .text
    static var psqlFormat: PostgresFormat { .text }

    func encode(
        into byteBuffer: inout ByteBuffer,
        context: PostgresEncodingContext<some PostgresNIO.PostgresJSONEncoder>
    ) throws {
        id.encode(into: &byteBuffer, context: context)
    }

    init(
        from byteBuffer: inout ByteBuffer,
        type: PostgresDataType,
        format: PostgresFormat,
        context: PostgresDecodingContext<some PostgresJSONDecoder>
    ) throws {
        let id: String = try .init(from: &byteBuffer, type: type, format: format, context: context)
        do {
            try self.init(id)
        } catch {
            throw DecodingError.typeMismatch(Self.self, .init(codingPath: [], debugDescription: "Unexpected value: \(id)"))
        }
    }
}

extension PackageStatus: PostgresCodable {
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
