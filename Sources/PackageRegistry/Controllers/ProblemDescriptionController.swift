import Hummingbird

enum ProblemType: String {
    case noAcceptHeader = "no-accept-header"
    case invalidAcceptHeader = "invalid-accept-header"
    case unsupportedAcceptVersion = "unsupported-accept-version"

    var url: String { "http://localhost:8080/errors/\(self.rawValue)" }
}

let errorDescriptions: [ProblemType: String] = [
    .noAcceptHeader: "A client SHOULD set the Accept header field to specify the API version of a request."
]

struct ErrorDescriptionController<Context: HBBaseRequestContext> {
    func addRoutes(to router: HBRouter<Context>) {
        router.get("errors/:code") { request, context in
            let code = try context.parameters.require("code", as: ProblemType.self)
            guard let description = errorDescriptions[code] else {
                throw HBHTTPError(.noContent)
            }
            return description
        }
    }
}