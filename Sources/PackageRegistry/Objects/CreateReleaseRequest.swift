import Foundation
import NIOCore
import NIOFoundationCompat

/// Create release object
///
/// refer to: https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#46-create-a-package-release
struct CreateReleaseRequest {
    let sourceArchiveDigest: String
    let sourceArchiveSignature: String?
    let metadata: Data?
    let metadataSignature: String?

    internal init(
        sourceArchiveDigest: String,
        sourceArchiveSignature: String? = nil,
        metadata: Data? = nil,
        metadataSignature: String? = nil
    ) {
        self.sourceArchiveDigest = sourceArchiveDigest
        self.sourceArchiveSignature = sourceArchiveSignature
        self.metadata = metadata
        self.metadataSignature = metadataSignature
    }

    func createRelease(id: PackageIdentifier, version: Version) throws -> PackageRelease {
        let resource = PackageRelease.Resource(
            name: "source-archive",
            type: "application/zip",
            checksum: self.sourceArchiveDigest,
            signing: sourceArchiveSignature.map {
                .init(signatureBase64Encoded: $0, signatureFormat: "cms-1.0.0")
            }
        )
        guard let metadata else {
            throw Problem(status: .unprocessableContent, detail: "Release metadata is required to publish release.")
        }
        var packageMetadata: PackageMetadata
        do {
            packageMetadata = try JSONDecoder().decode(PackageMetadata.self, from: metadata)
            if let repositoryURLs = packageMetadata.repositoryURLs {
                packageMetadata.repositoryURLs = repositoryURLs.map { $0.standardizedGitURL() }
            }
        } catch {
            throw Problem(status: .unprocessableContent, detail: "invalid JSON provided for release metadata.")
        }
        return .init(
            id: id,
            version: version,
            resources: [resource],
            metadata: packageMetadata,
            publishedAt: self.iso8601Formatter.string(from: .now)
        )
    }

    var iso8601Formatter: ISO8601DateFormatter {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withFullTime]
        return dateFormatter
    }
}

extension Sequence<UInt8> {
    /// return a hexEncoded string buffer from an array of bytes
    public func hexDigest() -> String {
        self.map { String(format: "%02x", $0) }.joined(separator: "")
    }
}
