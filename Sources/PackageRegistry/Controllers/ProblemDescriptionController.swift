import Hummingbird

enum ProblemType: String {
    case noAcceptHeader = "no-accept-header"
    case invalidAcceptHeader = "invalid-accept-header"
    case invalidContentType = "invalid-content-type"
    case invalidDigest = "invalid-digest"
    case invalidPackageIdentifier = "invalid-package-identifier"
    case invalidSignatureFormat = "invalid-signature-format"
    case unsupportedAcceptVersion = "unsupported-accept-version"
    case expectionsUnsupported = "expectations-unsupported"
    case versionAlreadyExists = "version-exists"

    var url: String { "https://localhost:8080/errors/\(rawValue)" }
}

let errorDescriptions: [ProblemType: String] = [
    .noAcceptHeader: "A client SHOULD set the Accept header field to specify the API version of a request.",
]

struct ErrorDescriptionController<Context: BaseRequestContext> {
    func addRoutes(to group: RouterGroup<Context>) {
        group.get("{code}") { _, context in
            let code = try context.parameters.require("code", as: ProblemType.self)
            guard let description = errorDescriptions[code] else {
                throw HTTPError(.noContent)
            }
            return description
        }
    }
}
