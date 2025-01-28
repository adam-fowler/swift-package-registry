import Foundation
import X509

protocol SignatureProvider {
    /// Verify signature and extract signing entity
    ///
    /// - Parameters:
    ///   - signatureBytes: Signature we are verifying
    ///   - verifierConfiguration: Signature verification configuration
    /// - Throws: SigningError, error found while verifying signature
    /// - Returns: Entity that signed the data
    func status(signatureBytes: [UInt8], verifierConfiguration: VerifierConfiguration) async throws(SigningError) -> SigningEntity

    /// Verify signature against contents and extract signing entity
    ///
    /// - Parameters:
    ///   - signatureBytes: Signature we are verifying
    ///   - content: Data that was signed
    ///   - verifierConfiguration: Signature verification configuration
    /// - Throws: SigningError, error found while verifying signature
    /// - Returns: Entity that signed the data
    func verify(
        signatureBytes: [UInt8],
        content: some DataProtocol,
        verifierConfiguration: VerifierConfiguration
    ) async throws(SigningError) -> SigningEntity
}
