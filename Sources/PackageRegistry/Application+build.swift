import Hummingbird
import HummingbirdBasicAuth
import HummingbirdCore
import HummingbirdPostgres
import HummingbirdTLS
import Jobs
import JobsPostgres
import Logging
import NIOSSL
import PostgresMigrations
import PostgresNIO
import ServiceLifecycle

/// Application arguments protocol. We use a protocol so we can call
/// `HBApplication.configure` inside Tests as well as in the App executable.
/// Any variables added here also have to be added to `App` in App.swift and
/// `TestArguments` in AppTest.swift
public protocol AppArguments: Sendable {
    var hostname: String { get }
    var port: Int { get }
    var inMemory: Bool { get }
    var revert: Bool { get }
    var migrate: Bool { get }
}

public func buildApplication(_ args: some AppArguments) async throws -> any ApplicationProtocol {
    let env = try await Environment().merging(with: .dotEnv())
    let serverName = env.get("server_name") ?? "localhost"
    let serverAddress = "\(serverName):\(args.port)"
    let logger = {
        var logger = Logger(label: "PackageRegistry")
        logger.logLevel = .debug
        return logger
    }()
    let router = Router(context: PackageRegistryRequestContext.self, options: .autoGenerateHeadEndpoints)
    router.add(middleware: LogRequestsMiddleware(.debug))
    router.add(middleware: ProblemMiddleware())
    router.get("/health") { _, _ -> HTTPResponse.Status in
        .ok
    }
    let storage = LocalFileStorage(rootFolder: "registry")

    var services: [any Service] = []
    var beforeServerStarts: (@Sendable () async throws -> Void)?
    let registryRoutes: RouteCollection<PackageRegistryRequestContext>
    if !args.inMemory {
        let postgresClient = PostgresClient(
            configuration: .init(host: "localhost", username: "spruser", password: "user", database: "swiftpackageregistry", tls: .disable),
            backgroundLogger: logger
        )
        let migrations = DatabaseMigrations()
        await migrations.add(CreatePackageRelease())
        await migrations.add(CreateURLPackageReference())
        await migrations.add(CreateManifest())
        await migrations.add(CreateUsers())
        await migrations.add(AddAdminUser())

        let jobQueue = await JobQueue(
            .postgres(
                client: postgresClient,
                migrations: migrations,
                configuration: .init(pollTime: .milliseconds(10)),
                logger: logger
            ),
            numWorkers: 1,
            logger: logger
        )
        let keyValueStore = await PostgresPersistDriver(client: postgresClient, migrations: migrations, logger: logger)
        let userRepository = PostgresUserRepository(client: postgresClient)
        let packageRepository = PostgresPackageReleaseRepository(client: postgresClient)
        let manifestRepository = PostgresManifestRepository(client: postgresClient)
        PublishJobController(
            storage: storage,
            packageRepository: packageRepository,
            manifestRepository: manifestRepository,
            publishStatusManager: .init(keyValueStore: keyValueStore)
        ).registerJobs(jobQueue: jobQueue)

        // Add package registry endpoints
        registryRoutes = PackageRegistryController(
            storage: storage,
            packageRepository: packageRepository,
            manifestRepository: manifestRepository,
            urlRoot: "https://\(serverAddress)/registry/",
            jobQueue: jobQueue,
            publishStatusManager: .init(keyValueStore: keyValueStore)
        ).routes(basicAuthenticator: BasicAuthenticator(repository: userRepository))

        services.append(postgresClient)
        services.append(jobQueue)
        services.append(keyValueStore)

        beforeServerStarts = {
            do {
                if args.revert {
                    try await migrations.revert(client: postgresClient, logger: logger, dryRun: false)
                }
                try await migrations.apply(client: postgresClient, logger: logger, dryRun: !(args.migrate || args.revert))
                try await PackageStatus.setDataType(client: postgresClient, logger: logger)
            } catch {
                print(String(reflecting: error))
                throw error
            }
        }
    } else {
        let userRepository = MemoryUserRepository()
        let jobQueue = JobQueue(
            .memory,
            numWorkers: 1,
            logger: logger
        )
        let keyValueStore = MemoryPersistDriver()
        let packageRepository = MemoryPackageReleaseRepository()
        let manifestRepository = MemoryManifestRepository()

        PublishJobController(
            storage: storage,
            packageRepository: packageRepository,
            manifestRepository: manifestRepository,
            publishStatusManager: .init(keyValueStore: keyValueStore)
        ).registerJobs(jobQueue: jobQueue)

        // Add package registry endpoints
        registryRoutes = PackageRegistryController(
            storage: storage,
            packageRepository: packageRepository,
            manifestRepository: manifestRepository,
            urlRoot: "https://\(serverAddress)/registry/",
            jobQueue: jobQueue,
            publishStatusManager: .init(keyValueStore: keyValueStore)
        ).routes(basicAuthenticator: BasicAuthenticator(repository: userRepository))

        services.append(jobQueue)
        services.append(keyValueStore)
    }

    router.add(middleware: OptionsMiddleware())
    router.group("registry").addRoutes(registryRoutes)

    var app: Application<RouterResponder<PackageRegistryRequestContext>>
    if let tlsCertificateChain = env.get("server_certificate_chain"),
        let tlsPrivateKey = env.get("server_private_key")
    {
        let tlsConfiguration = try getTLSConfiguration(certificateChain: tlsCertificateChain, privateKey: tlsPrivateKey)
        app = try Application(
            router: router,
            server: .tls(tlsConfiguration: tlsConfiguration),
            configuration: .init(
                address: .hostname(args.hostname, port: args.port),
                serverName: serverAddress
            ),
            services: services,
            logger: logger
        )
    } else {
        app = Application(
            router: router,
            configuration: .init(
                address: .hostname(args.hostname, port: args.port),
                serverName: serverAddress
            ),
            services: services,
            logger: logger
        )
    }

    if let beforeServerStarts {
        app.beforeServerStarts(perform: beforeServerStarts)
    }
    return app
}

func getTLSConfiguration(certificateChain: String, privateKey: String) throws -> TLSConfiguration {
    let certificateChain = try NIOSSLCertificate(bytes: [UInt8](certificateChain.utf8), format: .pem)  // .fromPEMFile(certificateChain)
    let privateKey = try NIOSSLPrivateKey(bytes: [UInt8](privateKey.utf8), format: .pem)
    return TLSConfiguration.makeServerConfiguration(
        certificateChain: [.certificate(certificateChain)],
        privateKey: .privateKey(privateKey)
    )
}
