/// Package identifier
/// 
/// as defined in https://github.com/apple/swift-package-manager/blob/main/Documentation/PackageRegistry/Registry.md#36-package-identification
struct PackageIdentifier {
    static let scopeRegex: Regex = /\A[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}\z/
    static let nameRegex: Regex = /\A[a-zA-Z0-9](?:[a-zA-Z0-9]|[-_](?=[a-zA-Z0-9])){0,99}\z/
    static let idRegex: Regex = /\A([a-zA-Z0-9_-]+).([a-zA-Z0-9_-]+)\z/
    let scope: String
    let name: String

    init?(_ identifier: String) {
        guard let match = identifier.wholeMatch(of: Self.idRegex) else { return nil }
        let (_, scope, name) = match.output
        guard name.wholeMatch(of: Self.nameRegex) != nil else { return nil }
        guard scope.wholeMatch(of: Self.scopeRegex) != nil else { return nil }
        
        self.name = String(name)
        self.scope = String(scope)
    }
}