// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [.enableUpcomingFeature("BareSlashRegexLiterals")]

let package = Package(
    name: "swift-package-registry",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.63.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", branch: "2.x.x"),
        .package(url: "https://github.com/vapor/multipart-kit.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.20.0"),
    ],
    targets: [
        .executableTarget(
            name: "PackageRegistry",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTLS", package: "hummingbird"),
                .product(name: "MultipartKit", package: "multipart-kit"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .byName(name: "Zip"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(name: "CMinizip"),
        .target(name: "Zip", dependencies: [
            "CMinizip",
            .product(name: "NIOPosix", package: "swift-nio"),
        ]),
        .testTarget(
            name: "PackageRegistryTests",
            dependencies: [
                .product(name: "HummingbirdXCT", package: "hummingbird"),
                "PackageRegistry",
            ]
        ),
    ]
)
