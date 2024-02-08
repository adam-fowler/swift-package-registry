import Hummingbird

enum ProblemType: String {
    case noAcceptHeader = "no-accept-header"
    case invalidAcceptHeader = "invalid-accept-header"
    case invalidContentType = "invalid-content-type"
    case invalidPackageIdentifier = "invalid-package-identifier"
    case unsupportedAcceptVersion = "unsupported-accept-version"
    case expectionsUnsupported = "expectations-unsupported"

    var url: String { "http://localhost:8080/errors/\(rawValue)" }
}

let errorDescriptions: [ProblemType: String] = [
    .noAcceptHeader: "A client SHOULD set the Accept header field to specify the API version of a request.",
]

struct ErrorDescriptionController<Context: HBBaseRequestContext> {
    func addRoutes(to group: HBRouterGroup<Context>) {
        group.get("{code}") { _, context in
            let code = try context.parameters.require("code", as: ProblemType.self)
            guard let description = errorDescriptions[code] else {
                throw HBHTTPError(.noContent)
            }
            return description
        }
    }
}
