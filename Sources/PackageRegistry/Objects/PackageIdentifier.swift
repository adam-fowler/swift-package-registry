/// Package identifier
///
/// as defined in https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#36-package-identification
struct PackageIdentifier: Hashable, Sendable, CustomStringConvertible {
    static let scopeRegex: Regex = /\A[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}\z/
    static let nameRegex: Regex = /\A[a-zA-Z0-9](?:[a-zA-Z0-9]|[-_](?=[a-zA-Z0-9])){0,99}\z/
    static let idRegex: Regex = /\A([a-zA-Z0-9_-]+).([a-zA-Z0-9_-]+)\z/
    let scope: String
    let name: String

    var id: String { "\(self.scope).\(self.name)" }
    var description: String { "\(self.scope).\(self.name)" }

    init<S: StringProtocol>(scope: S, name: S) throws where S.SubSequence == Substring {
        guard name.wholeMatch(of: Self.nameRegex) != nil,
              scope.wholeMatch(of: Self.scopeRegex) != nil
        else {
            throw Problem(
                status: .badRequest,
                type: ProblemType.invalidPackageIdentifier.url,
                detail: "Invalid package identifier. Must be of the form scope.name and only include alpha numeric characters, \"-\" and \"_\""
            )
        }

        self.name = String(name)
        self.scope = String(scope)
    }

    init(_ identifier: String) throws {
        guard let match = identifier.wholeMatch(of: Self.idRegex) else {
            throw Problem(
                status: .badRequest,
                type: ProblemType.invalidPackageIdentifier.url,
                detail: "Invalid package identifier. Must be of the form scope.name"
            )
        }
        let (_, scope, name) = match.output
        try self.init(scope: scope, name: name)
    }
}

extension PackageIdentifier: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let id = try container.decode(String.self)
        try self.init(id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.id)
    }
}
