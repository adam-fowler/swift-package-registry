import Crypto
import SwiftASN1
import X509
import _NIOFileSystem

struct SigningIdentity {
    let certificate: Certificate
    let privateKey: Certificate.PrivateKey

    init(
        certificate: [UInt8],
        privateKey: [UInt8]
    ) throws {
        self.certificate = try Certificate(derEncoded: certificate)
        self.privateKey = try Certificate.PrivateKey(P256.Signing.PrivateKey(derRepresentation: privateKey))
    }

    init(
        certificateFilename: String,
        privateKeyFilename: String
    ) async throws {
        let certificateFilenameContents = try await FileSystem.shared.withFileHandle(forReadingAt: .init(certificateFilename)) { fileHandle in
            var buffer = try await fileHandle.readToEnd(maximumSizeAllowed: .unlimited)
            return buffer.readString(length: buffer.readableBytes)!
        }
        let privateKeyFilenameContents = try await FileSystem.shared.withFileHandle(forReadingAt: .init(privateKeyFilename)) { fileHandle in
            var buffer = try await fileHandle.readToEnd(maximumSizeAllowed: .unlimited)
            return buffer.readString(length: buffer.readableBytes)!
        }
        try self.init(
            certificate: PEMDocument(pemString: certificateFilenameContents).derBytes,
            privateKey: PEMDocument(pemString: privateKeyFilenameContents).derBytes
        )
    }
}
