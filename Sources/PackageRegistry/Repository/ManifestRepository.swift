import NIOCore

struct ManifestVersion {
    let manifest: ByteBuffer
    let swiftVersion: String?
}
