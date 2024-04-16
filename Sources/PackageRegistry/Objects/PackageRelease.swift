import Hummingbird

/// Package release metadata
///
/// Refer to: https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#appendix-b---package-release-metadata-json-schema
struct PackageMetadata: Codable {
    struct Author: Codable {
        struct Organisation: Codable {
            let name: String
            let email: String?
            let description: String?
            let url: String?
        }

        let name: String
        let email: String?
        let description: String?
        let organisation: Organisation?
        let url: String?
    }

    let author: Author?
    let description: String?
    let licenseURL: String?
    let originalPublicationTime: String?
    let readmeURL: String?
    var repositoryURLs: [String]?
}

struct PackageReleaseIdentifier: Hashable, Equatable {
    let packageId: PackageIdentifier
    let version: Version

    var id: String { self.packageId.description + self.version.description }
}

/// Package release information
///
/// Refer to: https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#42-fetch-information-about-a-package-release
struct PackageRelease: Codable, ResponseEncodable {
    struct Resource: Codable {
        struct Signing: Codable {
            let signatureBase64Encoded: String
            let signatureFormat: String
        }

        let name: String
        let type: String
        let checksum: String
        let signing: Signing?
    }

    let id: PackageIdentifier
    let version: Version
    let resources: [Resource]
    let metadata: PackageMetadata?
    let publishedAt: String?

    var releaseID: PackageReleaseIdentifier { .init(packageId: self.id, version: self.version) }
}

extension String {
    func standardizedGitURL() -> String {
        self.dropSuffix("/").addSuffix(".git").lowercased()
    }
}
