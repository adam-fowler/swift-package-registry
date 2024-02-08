import Crypto
import Foundation

/// Create release object
///
/// refer to: https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#46-create-a-package-release
struct CreateReleaseRequest: Codable {
    let sourceArchive: Data
    let sourceArchiveSignature: Data?
    let metadata: PackageMetadata?
    let metadataSignature: Data?

    private enum CodingKeys: String, CodingKey {
        case sourceArchive = "source-archive"
        case sourceArchiveSignature = "source-archive-signature"
        case metadata
        case metadataSignature = "metadata-signature"
    }

    func createRelease(id: PackageIdentifier, version: Version) -> PackageRelease {
        let resource = PackageRelease.Resource(
            name: "source-archive",
            type: "application/zip",
            checksum: SHA256.hash(data: sourceArchive).hexDigest(),
            signing: nil
        )
        return .init(
            id: id, 
            version: version, 
            resources: [resource], 
            metadata: self.metadata, 
            publishedAt: self.iso8601Formatter.string(from: .now)
        )
    }

    var iso8601Formatter: ISO8601DateFormatter {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withFullTime]
        return dateFormatter
    }
}

public extension Sequence where Element == UInt8 {
    /// return a hexEncoded string buffer from an array of bytes
    func hexDigest() -> String {
        return self.map { String(format: "%02x", $0) }.joined(separator: "")
    }
}
