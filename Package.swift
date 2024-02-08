// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [.enableUpcomingFeature("BareSlashRegexLiterals")]

let package = Package(
    name: "PackageRegistry",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0-alpha.2"),
    ],
    targets: [
        .executableTarget(
            name: "PackageRegistry",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTLS", package: "hummingbird"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "PackageRegistryTests",
            dependencies: [
                .product(name: "HummingbirdXCT", package: "hummingbird"), 
                "PackageRegistry"
            ]
        ),
    ]
)
