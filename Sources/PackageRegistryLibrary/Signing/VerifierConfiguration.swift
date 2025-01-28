import Foundation
import X509

enum CertificateExpiration {
    case enabled(validationTime: Date?)
    case disabled
}

enum CertificateRevocation {
    case strict(validationTime: Date?)
    case allowSoftFail(validationTime: Date?)
    case disabled
}

struct VerifierConfiguration {
    let trustRoots: [Certificate]
    let certificateExpiration: CertificateExpiration
    let certificateRevocation: CertificateRevocation

    init(
        trustedRoots: [Certificate] = [],
        includeDefaultTrustRoots: Bool = true,
        certificateExpiration: CertificateExpiration = .enabled(validationTime: .now),
        certificateRevocation: CertificateRevocation = .allowSoftFail(validationTime: .now)
    ) {
        let defaultTrustRoots = includeDefaultTrustRoots ? Certificates.appleRoots : []
        let trustedRootCertificates = trustedRoots
        self.trustRoots = defaultTrustRoots + trustedRootCertificates
        self.certificateExpiration = certificateExpiration
        self.certificateRevocation = certificateRevocation
    }

    init(
        trustedRoots: [[UInt8]] = [],
        includeDefaultTrustRoots: Bool = true,
        certificateExpiration: CertificateExpiration = .enabled(validationTime: .now),
        certificateRevocation: CertificateRevocation = .allowSoftFail(validationTime: .now)
    ) throws {
        self.init(
            trustedRoots: try trustedRoots.map { try Certificate(derEncoded: $0) },
            includeDefaultTrustRoots: includeDefaultTrustRoots,
            certificateExpiration: certificateExpiration,
            certificateRevocation: certificateRevocation
        )
    }
}
