import StructuredFieldValues

extension StructuredFieldValueEncoder {
    public func encodeAsString<StructuredField: StructuredFieldValue>(_ data: StructuredField) throws -> String {
        try String(decoding: encode(data), as: UTF8.self)
    }
}

extension StructuredFieldValueDecoder {
    public func decode<StructuredField: StructuredFieldValue>(
        _ type: StructuredField.Type = StructuredField.self,
        from string: String
    ) throws -> StructuredField {
        let decoded = try string.utf8.withContiguousStorageIfAvailable { bytes in
            try self.decode(type, from: bytes)
        }
        if let decoded {
            return decoded
        }
        var string = string
        string.makeContiguousUTF8()
        return try self.decode(type, from: string)
    }
}

struct MultipartContentDispostion: StructuredFieldValue {
    struct Parameters: StructuredFieldValue {
        static let structuredFieldType: StructuredFieldType = .dictionary
        var name: String
    }
    static let structuredFieldType: StructuredFieldType = .item
    var item: String
    var parameters: Parameters
}

struct LinkHeader: StructuredFieldValue {
    static let structuredFieldType: StructuredFieldType = .list
    struct Item: StructuredFieldValue {
        static let structuredFieldType: StructuredFieldType = .item
        var item: String
        var parameters: [String: String]
    }
    var items: [Item]
}
