import Hummingbird
import HummingbirdCore
import HummingbirdPostgres
import HummingbirdTLS
import Logging
import NIOSSL
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
    let storage = FileStorage(rootFolder: "registry")

    let postgresClient: PostgresClient?
    let postgresMigrations: PostgresMigrations?
    let registryRoutes: RouteCollection<PackageRegistryRequestContext>
    if !args.inMemory {
        let client = PostgresClient(
            configuration: .init(host: "localhost", username: "spruser", password: "user", database: "swiftpackageregistry", tls: .disable),
            backgroundLogger: logger
        )
        let migrations = PostgresMigrations()
        await migrations.add(CreatePackageRelease())
        await migrations.add(CreateURLPackageReference())
        await migrations.add(CreateManifest())
        await migrations.add(CreateUsers())
        await migrations.add(AddAdminUser())

        let userRepository = PostgresUserRepository(client: client)
        // Add package registry endpoints
        registryRoutes = PackageRegistryController(
            storage: storage,
            packageRepository: PostgresPackageReleaseRepository(client: client),
            manifestRepository: PostgresManifestRepository(client: client),
            urlRoot: "https://\(serverAddress)/registry/"
        ).routes(basicAuthenticator: BasicAuthenticator(repository: userRepository))

        postgresClient = client
        postgresMigrations = migrations
    } else {
        let userRepository = MemoryUserRepository()
        // Add package registry endpoints
        registryRoutes = PackageRegistryController(
            storage: storage,
            packageRepository: MemoryPackageReleaseRepository(),
            manifestRepository: MemoryManifestRepository(),
            urlRoot: "https://\(serverAddress)/registry/"
        ).routes(basicAuthenticator: BasicAuthenticator(repository: userRepository))

        postgresClient = nil
        postgresMigrations = nil
    }

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
            logger: logger
        )
    } else {
        app = Application(
            router: router,
            configuration: .init(
                address: .hostname(args.hostname, port: args.port),
                serverName: serverAddress
            ),
            logger: logger
        )
    }

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

func getTLSConfiguration(certificateChain: String, privateKey: String) throws -> TLSConfiguration {
    let certificateChain = try NIOSSLCertificate(bytes: [UInt8](certificateChain.utf8), format: .pem) // .fromPEMFile(certificateChain)
    let privateKey = try NIOSSLPrivateKey(bytes: [UInt8](privateKey.utf8), format: .pem)
    return TLSConfiguration.makeServerConfiguration(
        certificateChain: [.certificate(certificateChain)],
        privateKey: .privateKey(privateKey)
    )
}
