import AsyncHTTPClient
import Foundation
@_spi(CMS) import X509

struct CMSSignatureProvider: SignatureProvider {
    let httpClient: HTTPClient

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
    ) async throws(SigningError) -> SigningEntity {
        let trustRoots: [Certificate] = verifierConfiguration.trustRoots

        let result = await CMS.isValidSignature(
            dataBytes: content,
            signatureBytes: signatureBytes,
            additionalIntermediateCertificates: self.untrustedIntermediates,
            trustRoots: CertificateStore(trustRoots)
        ) {
            self.buildPolicySet(
                configuration: verifierConfiguration,
                httpClient: self.httpClient
            )
        }

        switch result {
        case .success(let valid):
            let signingEntity = SigningEntity.from(certificate: valid.signer)
            return signingEntity
        case .failure(CMS.VerificationError.unableToValidateSigner(let failure)):
            if failure.validationFailures.isEmpty {
                let signingEntity = SigningEntity.from(certificate: failure.signer)
                throw SigningError.certificateNotTrusted(signingEntity)
            } else {
                throw SigningError.certificateInvalid(
                    "failures: \(failure.validationFailures.map(\.policyFailureReason))"
                )
            }
        case .failure(CMS.VerificationError.invalidCMSBlock(let error)):
            throw SigningError.invalid(error.reason)
        case .failure(let error):
            throw SigningError.invalid("\(error)")

        }
    }

    /// Verify signature and extract signing entity
    ///
    /// - Parameters:
    ///   - signatureBytes: Signature we are verifying
    ///   - verifierConfiguration: Signature verification configuration
    /// - Throws: SigningError, error found while verifying signature
    /// - Returns: Entity that signed the data
    func status(
        signatureBytes: [UInt8],
        verifierConfiguration: VerifierConfiguration
    ) async throws(SigningError) -> SigningEntity {
        let cmsSignature: CMSSignature
        let signers: [CMSSignature.Signer]
        do {
            cmsSignature = try CMSSignature(derEncoded: signatureBytes)
            signers = try cmsSignature.signers
        } catch {
            throw SigningError.invalid("Failed to parse signature: \(error)")
        }
        guard signers.count == 1, let signer = signers.first else {
            throw SigningError.signatureInvalid(
                "expected 1 signer but got \(signers.count)"
            )
        }
        let signingCertificate = signer.certificate

        var verifier = Verifier(rootCertificates: .init(verifierConfiguration.trustRoots)) {
            self.buildPolicySet(configuration: verifierConfiguration, httpClient: httpClient)
        }

        // The intermediates supplied here will be combined with those
        // included in the signature to build cert chain for validation.
        let result = await verifier.validate(
            leafCertificate: signingCertificate,
            intermediates: CertificateStore(self.untrustedIntermediates + cmsSignature.certificates)
        )

        switch result {
        case .validCertificate:
            let signingEntity = SigningEntity.from(certificate: signingCertificate)
            return signingEntity
        case .couldNotValidate(let validationFailures):
            if validationFailures.isEmpty {
                let signingEntity = SigningEntity.from(certificate: signingCertificate)
                throw SigningError.certificateNotTrusted(signingEntity)
            } else {
                throw SigningError.certificateInvalid("failures: \(validationFailures.map(\.policyFailureReason))")
            }
        }
    }

    // Those who use ADP certs for signing are not required to provide
    // the entire cert chain, thus we must supply WWDR intermediates
    // here so that the chain can be constructed during validation.
    // Whether the signing cert is trusted still depends on whether
    // the WWDR roots are in the trust store or not, which by default
    // they are but user may disable that through configuration.
    var untrustedIntermediates: [Certificate] {
        Certificates.wwdrIntermediates
    }
}
