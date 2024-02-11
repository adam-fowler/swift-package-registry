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
}

public func buildApplication(_ args: some AppArguments) async throws -> some HBApplicationProtocol {
    let logger = {
        var logger = Logger(label: "PackageRegistry")
        logger.logLevel = .debug
        return logger
    }()
    let router = HBRouter(context: RequestContext.self, options: .autoGenerateHeadEndpoints)
    router.middlewares.add(HBLogRequestsMiddleware(.debug))
    router.middlewares.add(VersionMiddleware(version: "1"))
    router.get("/health") { _, _ -> HTTPResponse.Status in
        .ok
    }

    var postgresClient: PostgresClient?
    let postgresMigrations: Migrations<PostgresMigrationRepository>?
    if !args.inMemory {
        let client = PostgresClient(
            configuration: .init(host: "localhost", username: "spruser", password: "user", database: "swiftpackageregistry", tls: .disable),
            backgroundLogger: logger
        )
        let migrations = Migrations(repository: PostgresMigrationRepository(client: client))
        postgresClient = client
        postgresMigrations = migrations
    } else {
        postgresMigrations = nil
    }

    let storage = FileStorage(rootFolder: "registry")
    // Add package registry endpoints
    PackageRegistryController(
        storage: storage,
        packageRepository: MemoryPackageReleaseRepository(),
        manifestRepository: MemoryManifestRepository()
    ).addRoutes(to: router.group("registry"))

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
                try await postgresMigrations?.migrate(logger: logger, dryRun: false)
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
