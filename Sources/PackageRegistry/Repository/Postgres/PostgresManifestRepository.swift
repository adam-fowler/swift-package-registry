import PostgresNIO

struct PostgresManifestRepository: ManifestRepository {
    let client: PostgresClient

    func add(_ id: PackageReleaseIdentifier, manifests: Manifests, logger: Logger) async throws {
        let defaultManifest = String(buffer: manifests.default)
        let manifestVersions = manifests.versions.map { String(buffer: $0.manifest) }
        let swiftVersions = manifests.versions.map(\.swiftVersion)
        _ = try await client.query(
            "INSERT INTO manifests VALUES (\(id.id), \(defaultManifest), \(manifestVersions), \(swiftVersions))",
            logger: logger
        )
    }

    func get(_ id: PackageReleaseIdentifier, logger: Logger) async throws -> Manifests? {
        let stream = try await client.query(
            "SELECT default_manifest, manifest_versions, swift_versions FROM manifests WHERE release_id = \(id.id)",
            logger: logger
        )
        for try await (defaultManifest, manifests, swiftVersions) in stream.decode((String, [String], [String]).self, context: .default) {
            var versions: [Manifests.Version] = []
            for i in 0..<min(manifests.count, swiftVersions.count) {
                versions.append(.init(manifest: ByteBuffer(string: manifests[i]), swiftVersion: swiftVersions[i]))
            }
            return .init(default: ByteBuffer(string: defaultManifest), versions: versions)
        }
        return nil
    }
}
