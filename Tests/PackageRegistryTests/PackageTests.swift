import Foundation
import HTTPTypes
import HummingbirdCore
import HummingbirdTesting
import MultipartKit
import NIOCore
import PackageRegistry
import Testing
import ZipArchive

@testable import PackageRegistryLibrary

@Suite("Test different packages")
struct PackageTests {
    static let packageDotSwift = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "test-package",
            products: [.library(name: "test-package", targets: ["test-package"])],
            targets: [
                .target(name: "test-package"),
                .testTarget(name: "test-packageTests", dependencies: ["test-package"]),
            ]
        )
        """

    func createPackageZipArchive(packageId: String, files: [String: String] = ["Package.swift": Self.packageDotSwift]) throws -> ArraySlice<UInt8> {
        let zipArchiveWriter = ZipArchiveWriter()
        for file in files {
            try zipArchiveWriter.writeFile(filename: "\(packageId)/\(file.key)", contents: .init(file.value.utf8))
        }
        return try zipArchiveWriter.finalizeBuffer()
    }

    func createMultipartForm<Bytes: RangeReplaceableCollection<UInt8> & Sendable>(
        packageArchive: Bytes,
        packageMetadata: PackageMetadata?,
        boundary: String
    ) throws -> Bytes {
        let multipartSerializer = MultipartSerializer(boundary: boundary)
        let multipartForm: Bytes =
            if let packageMetadata {
                try multipartSerializer.serialize(parts: [
                    .init(
                        headerFields: [
                            .contentDisposition: "form-data; name=\"source-archive\"",
                            .contentType: "application/zip",
                            .contentTransferEncoding: "binary",
                        ],
                        body: packageArchive
                    ),
                    .init(
                        headerFields: [
                            .contentDisposition: "form-date; name=\"metadata\"",
                            .contentType: "application/json",
                            .contentTransferEncoding: "quoted-printable",
                        ],
                        body: Bytes(JSONEncoder().encode(packageMetadata))
                    ),
                ])
            } else {
                try multipartSerializer.serialize(parts: [
                    .init(
                        headerFields: [
                            .contentDisposition: "form-data; name=\"source-archive\"",
                            .contentType: "application/zip",
                            .contentTransferEncoding: "binary",
                        ],
                        body: packageArchive
                    )
                ])
            }
        return multipartForm
    }

    static func uploadTestPackage(
        _ client: some TestClientProtocol,
        multipartBoundary: String,
        buffer: ByteBuffer,
        packageIdentifier: PackageIdentifier,
        version: String = "1.0.0"
    ) async throws -> TestResponse {
        try await client.execute(
            uri: "registry/\(packageIdentifier.scope)/\(packageIdentifier.name)/\(version)",
            method: .put,
            headers: [
                .accept: "application/vnd.swift.registry.v1",
                .contentType: "multipart/form-data;boundary=\(multipartBoundary)",
            ],
            auth: .basic(username: "admin", password: "Password123"),
            body: buffer
        ) { $0 }
    }

    static func waitForPackageToBeProcessed(
        _ client: some TestClientProtocol,
        location: String
    ) async throws -> TestResponse {
        let locationFullURI = URI(location)
        let locationURI = locationFullURI.path
        while true {
            try await Task.sleep(for: .milliseconds(100))
            let response = try await client.execute(
                uri: locationURI,
                method: .get,
                headers: [.accept: "application/vnd.swift.registry.v1"]
            ) { $0 }
            if response.status != .accepted {
                return response
            }
        }
    }

    @Test
    func simplePackage() async throws {
        let boundary = UUID().uuidString
        let packageArchive = try createPackageZipArchive(packageId: "test.test-package")
        let packageMetadata = PackageMetadata(
            author: .init(name: "Joe Bloggs", email: nil, description: nil, organisation: nil, url: nil),
            description: "Test package",
            licenseURL: nil,
            originalPublicationTime: nil,
            readmeURL: nil
        )
        let multipartForm = try createMultipartForm(packageArchive: packageArchive, packageMetadata: packageMetadata, boundary: boundary)

        let args = TestArguments()
        let app = try await buildApplication(args)
        try await app.test(.router) { client in
            let response = try await Self.uploadTestPackage(
                client,
                multipartBoundary: boundary,
                buffer: .init(bytes: multipartForm),
                packageIdentifier: .init("test.test-package")
            )
            #expect(response.status == .accepted)
            let location = try #require(response.headers[.location])

            let waitResponse = try await Self.waitForPackageToBeProcessed(client, location: location)
            #expect(waitResponse.status == .movedPermanently)
            #expect(waitResponse.headers[.location] == "https://\(args.hostname):\(args.port)/registry/test/test-package/1.0.0")
        }
    }

    @Test
    func withoutMetadata() async throws {
        let boundary = UUID().uuidString
        let packageArchive = try createPackageZipArchive(packageId: "test.test-package")
        let multipartForm = try createMultipartForm(packageArchive: packageArchive, packageMetadata: nil, boundary: boundary)

        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            let response = try await Self.uploadTestPackage(
                client,
                multipartBoundary: boundary,
                buffer: .init(bytes: multipartForm),
                packageIdentifier: .init("test.test-package")
            )
            #expect(response.status == .unprocessableContent)
            let problem = try JSONDecoder().decode(Problem.self, from: response.body)
            #expect(problem.detail == "Release metadata is required to publish release.")
        }
    }

    @Test
    func withoutManifest() async throws {
        let boundary = UUID().uuidString
        let packageArchive = try createPackageZipArchive(packageId: "test.test-package", files: ["package.json": "{}"])
        let packageMetadata = PackageMetadata(
            author: .init(name: "Joe Bloggs", email: nil, description: nil, organisation: nil, url: nil),
            description: "Test package",
            licenseURL: nil,
            originalPublicationTime: nil,
            readmeURL: nil
        )
        let multipartForm = try createMultipartForm(packageArchive: packageArchive, packageMetadata: packageMetadata, boundary: boundary)

        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            let response = try await Self.uploadTestPackage(
                client,
                multipartBoundary: boundary,
                buffer: .init(bytes: multipartForm),
                packageIdentifier: .init("test.test-package")
            )
            #expect(response.status == .accepted)
            let location = try #require(response.headers[.location])

            let waitResponse = try await Self.waitForPackageToBeProcessed(client, location: location)
            #expect(waitResponse.status == .unprocessableContent)
            let problem = try JSONDecoder().decode(Problem.self, from: waitResponse.body)
            #expect(problem.detail == "Package doesn't contain a valid manifest (Package.swift) file")
        }
    }

    @Test
    func withMultipleManifests() async throws {
        let packageDotSwift5_10 = """
            // swift-tools-version: 5.10
            import PackageDescription

            let package = Package(
                name: "test-package",
                products: [.library(name: "test-package", targets: ["test-package"])],
                targets: [
                    .target(name: "test-package"),
                    .testTarget(name: "test-packageTests", dependencies: ["test-package"]),
                ]
            )
            """
        let boundary = UUID().uuidString
        let packageArchive = try createPackageZipArchive(
            packageId: "test.test-package",
            files: [
                "Package.swift": Self.packageDotSwift,
                "Package@swift-5.10.swift": packageDotSwift5_10,
            ]
        )
        let packageMetadata = PackageMetadata(
            author: .init(name: "Joe Bloggs", email: nil, description: nil, organisation: nil, url: nil),
            description: "Test package",
            licenseURL: nil,
            originalPublicationTime: nil,
            readmeURL: nil
        )
        let multipartForm = try createMultipartForm(packageArchive: packageArchive, packageMetadata: packageMetadata, boundary: boundary)

        let args = TestArguments()
        let app = try await buildApplication(args)
        try await app.test(.router) { client in
            let response = try await Self.uploadTestPackage(
                client,
                multipartBoundary: boundary,
                buffer: .init(bytes: multipartForm),
                packageIdentifier: .init("test.test-package")
            )
            #expect(response.status == .accepted)
            let location = try #require(response.headers[.location])

            let waitResponse = try await Self.waitForPackageToBeProcessed(client, location: location)
            #expect(waitResponse.status == .movedPermanently)
            #expect(waitResponse.headers[.location] == "https://\(args.hostname):\(args.port)/registry/test/test-package/1.0.0")

            // test manifest
            try await client.execute(
                uri: "/registry/test/test-package/1.0.0/Package.swift",
                method: .get,
                headers: [.accept: "application/vnd.swift.registry.v1"]
            ) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).hasPrefix("// swift-tools-version: 6.0"))
            }

            // test 5.10 manifest
            try await client.execute(
                uri: "/registry/test/test-package/1.0.0/Package.swift?swift-version=5.10",
                method: .get,
                headers: [.accept: "application/vnd.swift.registry.v1"]
            ) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).hasPrefix("// swift-tools-version: 5.10"))
            }
        }
    }

    // Test responee when uploading version of package that is currently being processed
    @Test
    func uploadWhileProcessing() async throws {
        let boundary = UUID().uuidString
        let packageArchive = try createPackageZipArchive(packageId: "test.test-package")
        let packageMetadata = PackageMetadata(
            author: .init(name: "Joe Bloggs", email: nil, description: nil, organisation: nil, url: nil),
            description: "Test package",
            licenseURL: nil,
            originalPublicationTime: nil,
            readmeURL: nil
        )
        let multipartForm = try createMultipartForm(packageArchive: packageArchive, packageMetadata: packageMetadata, boundary: boundary)

        let appArgs = TestArguments()
        let app = try await buildApplication(appArgs)
        try await app.test(.router) { client in
            let response = try await Self.uploadTestPackage(
                client,
                multipartBoundary: boundary,
                buffer: .init(bytes: multipartForm),
                packageIdentifier: .init("test.test-package")
            )
            #expect(response.status == .accepted)
            #expect(response.headers[.retryAfter] != nil)

            let response2 = try await Self.uploadTestPackage(
                client,
                multipartBoundary: boundary,
                buffer: .init(bytes: multipartForm),
                packageIdentifier: .init("test.test-package")
            )
            #expect(response2.status == .conflict)
            let problem = try JSONDecoder().decode(Problem.self, from: response2.body)
            #expect(problem.type == ProblemType.versionAlreadyExists.url)
        }
    }

    @Test
    func uploadingMultipleVersions() async throws {
        struct Releases: Codable {
            struct Release: Codable {
                let url: String
            }
            let releases: [String: Release]
        }
        let boundary = UUID().uuidString
        let packageArchive = try createPackageZipArchive(packageId: "test.test-package")
        let packageMetadata = PackageMetadata(
            author: .init(name: "Joe Bloggs", email: nil, description: nil, organisation: nil, url: nil),
            description: "Test package",
            licenseURL: nil,
            originalPublicationTime: nil,
            readmeURL: nil
        )
        let multipartForm = try createMultipartForm(packageArchive: packageArchive, packageMetadata: packageMetadata, boundary: boundary)

        let appArgs = TestArguments()
        let app = try await buildApplication(appArgs)
        let versions = ["1.0.0", "1.1.0", "1.1.1"]
        try await app.test(.router) { client in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for version in versions {
                    group.addTask {
                        let response = try await Self.uploadTestPackage(
                            client,
                            multipartBoundary: boundary,
                            buffer: .init(bytes: multipartForm),
                            packageIdentifier: .init("test.test-package"),
                            version: version
                        )
                        #expect(response.status == .accepted)
                        let location = try #require(response.headers[.location])

                        let waitResponse = try await Self.waitForPackageToBeProcessed(client, location: location)
                        #expect(waitResponse.status == .movedPermanently)
                        #expect(
                            waitResponse.headers[.location] == "https://\(appArgs.hostname):\(appArgs.port)/registry/test/test-package/\(version)"
                        )
                    }
                }
                try await group.waitForAll()
            }

            // test release list
            try await client.execute(
                uri: "/registry/test/test-package",
                method: .get,
                headers: [.accept: "application/vnd.swift.registry.v1"]
            ) { response in
                #expect(response.status == .ok)
                let releases = try JSONDecoder().decode(Releases.self, from: response.body)
                #expect(releases.releases.count == versions.count)
                for version in versions {
                    #expect(releases.releases[version]?.url == "https://\(appArgs.hostname):\(appArgs.port)/registry/test/test-package/\(version)")
                    print(response.headers)
                }
            }

        }
    }

}

extension HTTPField.Name {
    static let contentTransferEncoding: Self = .init("Content-Transfer-Encoding")!
}
