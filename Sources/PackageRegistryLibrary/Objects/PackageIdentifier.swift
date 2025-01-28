/// Package identifier
///
/// as defined in https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#36-package-identification
public struct PackageIdentifier: Hashable, Sendable, CustomStringConvertible {
    public let scope: String
    public let name: String

    public var id: String { "\(self.scope).\(self.name)" }
    public var description: String { "\(self.scope).\(self.name)" }

    public init<S: StringProtocol>(scope: S, name: S) throws where S.SubSequence == Substring {
        let nameRegex = /\A[a-zA-Z0-9](?:[a-zA-Z0-9]|[-_](?=[a-zA-Z0-9])){0,99}\z/
        let scopeRegex = /\A[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}\z/
        guard name.wholeMatch(of: nameRegex) != nil,
            scope.wholeMatch(of: scopeRegex) != nil
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

    public init(_ identifier: String) throws {
        let idRegex = /\A([a-zA-Z0-9_-]+).([a-zA-Z0-9_-]+)\z/
        guard let match = identifier.wholeMatch(of: idRegex) else {
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
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let id = try container.decode(String.self)
        try self.init(id)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.id)
    }
}
