import AsyncHTTPClient
import Hummingbird
import HummingbirdBasicAuth
import HummingbirdBcrypt
import HummingbirdCore
import HummingbirdPostgres
import HummingbirdTLS
import Jobs
import JobsPostgres
import Logging
import NIOSSL
import PackageRegistryLibrary
import PostgresMigrations
import PostgresNIO
import ServiceLifecycle
import SwiftASN1

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

    var tlsConfiguration: TLSConfiguration?
    if let tlsCertificateChain = env.get("server_certificate_chain"),
        let tlsPrivateKey = env.get("server_private_key")
    {
        tlsConfiguration = try getTLSConfiguration(certificateChain: tlsCertificateChain, privateKey: tlsPrivateKey)
    }
    let httpClient = HTTPClient()

    do {
        let router: Router<AppRequestContext>
        var services: [any Service] = [HTTPClientService(client: httpClient)]
        var beforeServerStarts: (@Sendable () async throws -> Void)?
        if !args.inMemory {
            let postgresClient = PostgresClient(
                configuration: .init(host: "localhost", username: "spruser", password: "spruser", database: "swiftpackageregistry", tls: .disable),
                backgroundLogger: logger
            )
            let migrations = DatabaseMigrations()
            await migrations.addPackageRegistryMigrations()

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

            let fileStorage = LocalFileStorage(rootFolder: "registry")
            let keyValueStore = await PostgresPersistDriver(client: postgresClient, migrations: migrations, logger: logger)
            let userRepository = PostgresUserRepository(client: postgresClient)
            let packageRepository = PostgresPackageReleaseRepository(client: postgresClient)
            let manifestRepository = PostgresManifestRepository(client: postgresClient)

            router = buildRouter(
                https: tlsConfiguration != nil,
                serverAddress: serverAddress,
                keyValueStore: keyValueStore,
                jobQueue: jobQueue,
                fileStorage: fileStorage,
                userRepository: userRepository,
                packageRepository: packageRepository,
                manifestRepository: manifestRepository
            )

            try registerJobs(
                env: env,
                jobQueue: jobQueue,
                keyValueStore: keyValueStore,
                fileStorage: fileStorage,
                httpClient: httpClient,
                packageRepository: packageRepository,
                manifestRepository: manifestRepository
            )

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
            let fileStorage = MemoryFileStorage()
            let keyValueStore = MemoryPersistDriver()
            let packageRepository = MemoryPackageReleaseRepository()
            let manifestRepository = MemoryManifestRepository()

            // given everything is new with every run, have to create an admin user every time
            let password = "Password123"
            logger.critical("User 'admin' password is \(password)")
            let passwordHash = try await NIOThreadPool.singleton.runIfActive { Bcrypt.hash("Password123", cost: 12) }
            try await userRepository.add(user: .init(id: .init(), username: "admin", passwordHash: passwordHash), logger: logger)

            router = buildRouter(
                https: true,
                serverAddress: serverAddress,
                keyValueStore: keyValueStore,
                jobQueue: jobQueue,
                fileStorage: fileStorage,
                userRepository: userRepository,
                packageRepository: packageRepository,
                manifestRepository: manifestRepository
            )

            try registerJobs(
                env: env,
                jobQueue: jobQueue,
                keyValueStore: keyValueStore,
                fileStorage: fileStorage,
                httpClient: httpClient,
                packageRepository: packageRepository,
                manifestRepository: manifestRepository
            )

            services.append(jobQueue)
            services.append(keyValueStore)
        }

        var app: Application<RouterResponder<AppRequestContext>>
        if let tlsConfiguration {
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
    } catch {
        try await httpClient.shutdown()
        throw error
    }
}

func getTLSConfiguration(certificateChain: String, privateKey: String) throws -> TLSConfiguration {
    let certificateChain = try NIOSSLCertificate(bytes: [UInt8](certificateChain.utf8), format: .pem)  // .fromPEMFile(certificateChain)
    let privateKey = try NIOSSLPrivateKey(bytes: [UInt8](privateKey.utf8), format: .pem)
    return TLSConfiguration.makeServerConfiguration(
        certificateChain: [.certificate(certificateChain)],
        privateKey: .privateKey(privateKey)
    )
}

func buildRouter(
    https: Bool,
    serverAddress: String,
    keyValueStore: some PersistDriver,
    jobQueue: JobQueue<some JobQueueDriver>,
    fileStorage: some FileStorage,
    userRepository: some UserRepository,
    packageRepository: some PackageReleaseRepository,
    manifestRepository: some ManifestRepository
) -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self, options: .autoGenerateHeadEndpoints)
    router.addMiddleware {
        LogRequestsMiddleware(.debug)
        OptionsMiddleware()
    }
    router.get("/health") { _, _ -> HTTPResponse.Status in
        .ok
    }
    if https {
        router.group("registry")
            .addRoutes(
                PackageRegistryController(
                    storage: fileStorage,
                    packageRepository: packageRepository,
                    manifestRepository: manifestRepository,
                    urlRoot: "https://\(serverAddress)/registry/",
                    jobQueue: jobQueue,
                    publishStatusManager: .init(keyValueStore: keyValueStore)
                ).routes(users: userRepository)
            )
    } else {
        router.group("registry")
            .addRoutes(
                PackageRegistryController(
                    storage: fileStorage,
                    packageRepository: packageRepository,
                    manifestRepository: manifestRepository,
                    urlRoot: "http://\(serverAddress)/registry/",
                    jobQueue: jobQueue,
                    publishStatusManager: .init(keyValueStore: keyValueStore)
                ).routes()
            )
    }

    return router
}

func registerJobs(
    env: Environment,
    jobQueue: JobQueue<some JobQueueDriver>,
    keyValueStore: some PersistDriver,
    fileStorage: some FileStorage,
    httpClient: HTTPClient,
    packageRepository: some PackageReleaseRepository,
    manifestRepository: some ManifestRepository
) throws {
    let trustedRoots: [[UInt8]] =
        if let trustRootsPEM = env.get("package_signing_trusted_roots") {
            [try PEMDocument(pemString: trustRootsPEM).derBytes]
        } else {
            []
        }
    let packageSignatureVerification = try PackageSignatureVerification(
        trustedRoots: trustedRoots,
        allowUntrustedCertificates: env.get("package_signing_allow_untrusted", as: Bool.self) ?? false
    )
    PublishJobController(
        storage: fileStorage,
        packageRepository: packageRepository,
        manifestRepository: manifestRepository,
        publishStatusManager: .init(keyValueStore: keyValueStore),
        httpClient: httpClient,
        packageSignatureVerification: packageSignatureVerification
    ).registerJobs(jobQueue: jobQueue)
}
