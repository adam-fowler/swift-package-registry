import HTTPTypes
import Hummingbird
import NIOCore

/// Error type used to generate Error output as detailed in RFC 7807
/// https://datatracker.ietf.org/doc/html/rfc7807
struct Problem: Error, Encodable, HBHTTPResponseError {
    let status: HTTPResponse.Status
    let type: String?
    let detail: String?
    let title: String?
    let instance: String?

    var headers: HTTPFields { [
        .contentType: "application/problem+json",
        .contentLanguage: "en",
        .contentVersion: "1",
    ] }

    init(
        status: HTTPResponse.Status,
        type: String? = nil,
        detail: String? = nil,
        title: String? = nil,
        instance: String? = nil
    ) {
        self.status = status
        self.type = type
        self.detail = detail
        self.title = title
        self.instance = instance
    }

    func body(allocator: ByteBufferAllocator) -> ByteBuffer? {
        try? JSONEncoder().encodeAsByteBuffer(self, allocator: allocator)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case detail
        case instance
    }
}
