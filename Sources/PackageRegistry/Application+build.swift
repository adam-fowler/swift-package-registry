import Hummingbird
import HummingbirdTLS
import Logging
import NIOSSL
@_spi(ConnectionPool) import PostgresNIO

/// Application arguments protocol. We use a protocol so we can call
/// `HBApplication.configure` inside Tests as well as in the App executable.
/// Any variables added here also have to be added to `App` in App.swift and
/// `TestArguments` in AppTest.swift
public protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
    var inMemory: Bool { get }
    var revert: Bool { get }
}

public func buildApplication(_ args: some AppArguments) async throws -> some HBApplicationProtocol {
    let logger = {
        var logger = Logger(label: "PackageRegistry")
        logger.logLevel = .debug
        return logger
    }()
    let router = HBRouter(context: RequestContext.self, options: .autoGenerateHeadEndpoints)
    router.middlewares.add(ProblemMiddleware())
    router.middlewares.add(HBLogRequestsMiddleware(.debug))
    router.get("/health") { _, _ -> HTTPResponse.Status in
        .ok
    }
    let storage = FileStorage(rootFolder: "registry")

    var postgresClient: PostgresClient?
    let postgresMigrations: Migrations<PostgresMigrationRepository>?
    if !args.inMemory {
        let client = PostgresClient(
            configuration: .init(host: "localhost", username: "spruser", password: "user", database: "swiftpackageregistry", tls: .disable),
            backgroundLogger: logger
        )
        let migrations = Migrations(repository: PostgresMigrationRepository(client: client))
        await migrations.add(CreatePackageRelease())
        await migrations.add(CreateURLPackageReference())
        await migrations.add(CreateManifest())

        // Add package registry endpoints
        PackageRegistryController(
            storage: storage,
            packageRepository: PostgresPackageReleaseRepository(client: client),
            manifestRepository: PostgresManifestRepository(client: client)
        ).addRoutes(to: router.group("registry"))

        postgresClient = client
        postgresMigrations = migrations
    } else {
        // Add package registry endpoints
        PackageRegistryController(
            storage: storage,
            packageRepository: MemoryPackageReleaseRepository(),
            manifestRepository: MemoryManifestRepository()
        ).addRoutes(to: router.group("registry"))
        postgresMigrations = nil
    }

    var app = try HBApplication(
        router: router,
        server: .tls(tlsConfiguration: tlsConfiguration),
        configuration: .init(
            address: .hostname(args.hostname, port: args.port),
            serverName: "localhost:8080"
        ),
        logger: logger
    )

    if let postgresClient {
        app.addServices(PostgresClientService(client: postgresClient))
        app.runBeforeServerStart {
            do {
                if args.revert {
                    try await postgresMigrations?.revert(logger: logger, dryRun: false)
                }
                try await postgresMigrations?.migrate(logger: logger, dryRun: false)
                try await PackageStatus.setDataType(client: postgresClient, logger: logger)
            } catch {
                print(String(reflecting: error))
                throw error
            }
        }
    }
    return app
}

var tlsConfiguration: TLSConfiguration {
    get throws {
        let certificateChain = try NIOSSLCertificate.fromPEMFile("certs/localhost.pem")
        let privateKey = try NIOSSLPrivateKey(file: "certs/localhost-key.pem", format: .pem)
        return TLSConfiguration.makeServerConfiguration(
            certificateChain: certificateChain.map { .certificate($0) },
            privateKey: .privateKey(privateKey)
        )
    }
}
