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
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.63.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-postgres.git", from: "0.5.0"),
        .package(url: "https://github.com/vapor/multipart-kit.git", branch: "v5"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    targets: [
        .executableTarget(
            name: "PackageRegistry",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
                .product(name: "HummingbirdBasicAuth", package: "hummingbird-auth"),
                .product(name: "HummingbirdBcrypt", package: "hummingbird-auth"),
                .product(name: "HummingbirdPostgres", package: "hummingbird-postgres"),
                .product(name: "PostgresMigrations", package: "hummingbird-postgres"),
                .product(name: "HummingbirdTLS", package: "hummingbird"),
                .product(name: "MultipartKit", package: "multipart-kit"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .byName(name: "Zip"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(name: "CMinizip", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "Zip", dependencies: [
            "CMinizip",
            .product(name: "NIOPosix", package: "swift-nio"),
        ]),
        .testTarget(
            name: "PackageRegistryTests",
            dependencies: [
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                "PackageRegistry",
            ]
        ),
    ]
)
