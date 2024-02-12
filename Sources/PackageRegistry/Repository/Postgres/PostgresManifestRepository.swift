@_spi(ConnectionPool) import PostgresNIO

struct PostgresManifestRepository: ManifestRepository {
    typealias Context = PostgresContext

    let client: PostgresClient

    func withContext<Value>(logger: Logger, _ process: (Context) async throws -> Value) async throws -> Value {
        try await self.client.withConnection { connection in
            try await process(.init(connection: connection, logger: logger))
        }
    }

    func add(_ id: PackageReleaseIdentifier, manifests: Manifests, context: Context) async throws {
        let defaultManifest = String(buffer: manifests.default)
        let manifestVersions = manifests.versions.map { String(buffer: $0.manifest) }
        let swiftVersions = manifests.versions.map(\.swiftVersion)
        _ = try await context.connection.query(
            "INSERT INTO manifests VALUES (\(id.id), \(defaultManifest), \(manifestVersions), \(swiftVersions))",
            logger: context.logger
        )
    }

    func get(_ id: PackageReleaseIdentifier, context: Context) async throws -> Manifests? {
        let stream = try await context.connection.query(
            "SELECT default_manifest, manifest_versions, swift_versions FROM manifests WHERE release_id = \(id.id)",
            logger: context.logger
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
