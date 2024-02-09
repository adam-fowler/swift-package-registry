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
    let repositoryURLs: [String]?
}

/// Package release information
///
/// Refer to: https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#42-fetch-information-about-a-package-release
struct PackageRelease: Codable, HBResponseEncodable {
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
}
