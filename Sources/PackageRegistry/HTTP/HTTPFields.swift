import HTTPTypes

extension HTTPField.Name {
    static var link: Self { .init("Link")! }
    static var digest: Self { .init("Digest")! }
    static var swiftPMSignature: Self { .init("X-Swift-Package-Signature")! }
    static var swiftPMSignatureFormat: Self { .init("X-Swift-Package-Signature-Format")! }
    /// Used in VersionMiddleware
    static var contentVersion: Self { .init("Content-Version")! }
}
