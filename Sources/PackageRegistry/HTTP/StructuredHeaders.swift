import StructuredFieldValues

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
