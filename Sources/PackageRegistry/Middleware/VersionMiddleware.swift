import HTTPTypes
import Hummingbird
import RegexBuilder

struct VersionMiddleware<Context: RequestContext>: RouterMiddleware {
    let version: String
    /// Accept header regex as defined in
    /// https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#35-api-versioning
    let acceptRegex = Regex {
        "application/vnd.swift.registry"
        Optionally {
            ".v"
            Capture {
                OneOrMore(.digit)
            }
        }
        Optionally {
            "+"
            ChoiceOf {
                "swift"
                "json"
                "zip"
            }
        }
    }

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        guard let accept = request.headers[.accept] else {
            throw Problem(
                status: .badRequest,
                type: ProblemType.noAcceptHeader.url,
                detail: "A client SHOULD set the Accept header field to specify the API version of a request."
            )
        }
        guard let match = accept.wholeMatch(of: acceptRegex) else {
            throw Problem(
                status: .notAcceptable,
                type: ProblemType.invalidAcceptHeader.url,
                detail: "The Accept header field should be of the form \"application/vnd.swift.registry\" [\".v\" version] [\"+\" mediatype]\"."
            )
        }
        let (_, version) = match.output
        if let version, version != self.version {
            throw Problem(
                status: .badRequest,
                type: ProblemType.unsupportedAcceptVersion.url,
                detail: "invalid API version."
            )
        }
        do {
            var response = try await next(request, context)
            response.headers[.contentVersion] = self.version
            return response
        } catch let error as HTTPError {
            var error = error
            error.headers[.contentVersion] = self.version
            throw error
        }
    }
}

// Regex isn't sendable
extension VersionMiddleware: @unchecked Sendable {}
