import Hummingbird
import HummingbirdPostgres
import HummingbirdTLS
import Logging
import NIOSSL
import OpenAPIHummingbird
import PostgresNIO

/// Application arguments protocol. We use a protocol so we can call
/// `HBApplication.configure` inside Tests as well as in the App executable.
/// Any variables added here also have to be added to `App` in App.swift and
/// `TestArguments` in AppTest.swift
public protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
    var inMemory: Bool { get }
    var revert: Bool { get }
    var migrate: Bool { get }
}

public func buildApplication(_ args: some AppArguments) async throws -> some ApplicationProtocol {
    let serverName = "localhost"
    let serverAddress = "\(serverName):\(args.port)"
    let logger = {
        var logger = Logger(label: "PackageRegistry")
        logger.logLevel = .debug
        return logger
    }()
    let router = Router(context: PackageRegistryRequestContext.self, options: .autoGenerateHeadEndpoints)
    router.middlewares.add(ProblemMiddleware())
    router.middlewares.add(LogRequestsMiddleware(.debug))
    router.get("/health") { _, _ -> HTTPResponse.Status in
        .ok
    }
    let storage = FileStorage(rootFolder: "registry")

    var postgresClient: PostgresClient?
    let postgresMigrations: PostgresMigrations?

    let registryGroup = router.group("registry")
        .add(middleware: TaskLocalContextMiddleware())
        
    if !args.inMemory {
        let client = PostgresClient(
            configuration: .init(host: "localhost", username: "spruser", password: "user", database: "swiftpackageregistry", tls: .disable),
            backgroundLogger: logger
        )
        let migrations = PostgresMigrations()
        await migrations.add(CreatePackageRelease())
        await migrations.add(CreateURLPackageReference())
        await migrations.add(CreateManifest())

        let api = PackageRegistryImplementationl(
            storage: storage,
            packageRepository: PostgresPackageReleaseRepository(client: client),
            manifestRepository: PostgresManifestRepository(client: client),
            urlRoot: "https://\(serverAddress)/registry/"
        )
        try api.registerHandlers(on: registryGroup)
        
        postgresClient = client
        postgresMigrations = migrations
    } else {
        // Add package registry endpoints
        let api = PackageRegistryImplementationl(
            storage: storage,
            packageRepository: MemoryPackageReleaseRepository(),
            manifestRepository: MemoryManifestRepository(),
            urlRoot: "https://\(serverAddress)/registry/"
        )
        try api.registerHandlers(on: registryGroup)
        postgresMigrations = nil
    }

    var app = try Application(
        router: router,
        server: .tls(tlsConfiguration: tlsConfiguration),
        configuration: .init(
            address: .hostname(args.hostname, port: args.port),
            serverName: serverAddress
        ),
        logger: logger
    )

    if let postgresClient {
        app.addServices(postgresClient)
        app.runBeforeServerStart {
            do {
                if args.revert {
                    try await postgresMigrations?.revert(client: postgresClient, logger: logger, dryRun: false)
                }
                try await postgresMigrations?.apply(client: postgresClient, logger: logger, dryRun: !(args.migrate || args.revert))
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
        let certificateChain = try NIOSSLCertificate.fromPEMFile("resources/certs/localhost.pem")
        let privateKey = try NIOSSLPrivateKey(file: "resources/certs/localhost-key.pem", format: .pem)
        return TLSConfiguration.makeServerConfiguration(
            certificateChain: certificateChain.map { .certificate($0) },
            privateKey: .privateKey(privateKey)
        )
    }
}
