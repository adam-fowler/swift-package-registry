// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = []

let package = Package(
    name: "swift-package-registry",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.77.0"),
        .package(url: "https://github.com/apple/swift-http-structured-headers", from: "1.2.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-postgres.git", from: "0.5.0"),
        .package(url: "https://github.com/hummingbird-project/swift-jobs-postgres.git", from: "1.0.0-beta"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.0.0-beta"),
        .package(url: "https://github.com/vapor/multipart-kit.git", branch: "main"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    targets: [
        .executableTarget(
            name: "PackageRegistry",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
                .product(name: "HummingbirdBasicAuth", package: "hummingbird-auth"),
                .product(name: "HummingbirdBcrypt", package: "hummingbird-auth"),
                .product(name: "HummingbirdPostgres", package: "hummingbird-postgres"),
                .product(name: "HummingbirdTLS", package: "hummingbird"),
                .product(name: "JobsPostgres", package: "swift-jobs-postgres"),
                .product(name: "MultipartKit", package: "multipart-kit"),
                .product(name: "_NIOFileSystem", package: "swift-nio"),
                .product(name: "PostgresMigrations", package: "hummingbird-postgres"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "StructuredFieldValues", package: "swift-http-structured-headers"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "X509", package: "swift-certificates"),
                .byName(name: "Zip"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(name: "CMinizip", linkerSettings: [.linkedLibrary("z")]),
        .target(
            name: "Zip",
            dependencies: [
                "CMinizip",
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "PackageRegistryTests",
            dependencies: [
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                "PackageRegistry",
            ]
        ),
    ]
)
