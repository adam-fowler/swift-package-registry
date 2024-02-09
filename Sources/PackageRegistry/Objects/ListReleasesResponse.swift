import HTTPTypes
import Hummingbird

/// Response return by list package releases request
///
/// refer to: https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#41-list-package-releases
struct ListReleaseResponse: HBResponseEncodable {
    struct Release: Codable {
        struct Problem: Codable {
            let status: Int
            let title: String
            let detail: String

            init(status: HTTPResponse.Status, detail: String) {
                self.status = status.code
                self.title = status.reasonPhrase
                self.detail = detail
            }
        }

        let url: String
        let problem: Problem?
    }

    let releases: [String: Release]
}
