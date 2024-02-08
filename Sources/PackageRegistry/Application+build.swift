import Hummingbird
import HummingbirdTLS
import Logging
import NIOSSL

/// Application arguments protocol. We use a protocol so we can call
/// `HBApplication.configure` inside Tests as well as in the App executable.
/// Any variables added here also have to be added to `App` in App.swift and
/// `TestArguments` in AppTest.swift
public protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
}

public func buildApplication(_ arguments: some AppArguments) async throws -> some HBApplicationProtocol {
    var logger = Logger(label: "PackageRegistry")
    logger.logLevel = .debug
    let router = HBRouter(context: RequestContext.self, options: .autoGenerateHeadEndpoints)
    router.middlewares.add(HBLogRequestsMiddleware(.debug))
    router.middlewares.add(VersionMiddleware(version: "1"))
    router.get("/health") { _, _ -> HTTPResponse.Status in
        .ok
    }

    let storage = FileStorage(rootFolder: "registry")
    // Add package registry endpoints
    PackageRegistryController(storage: storage).addRoutes(to: router.group("registry"))

    let app = try HBApplication(
        router: router,
        server: .tls(tlsConfiguration: tlsConfiguration),
        configuration: .init(
            address: .hostname(arguments.hostname, port: arguments.port),
            serverName: "localhost:8080"
        ),
        logger: logger
    )
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
