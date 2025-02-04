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
        let multipartSerializer = MultipartSerializer(boundary: boundary)
        let multipartForm: [UInt8] = try multipartSerializer.serialize(parts: [
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
                body: .init(JSONEncoder().encode(packageMetadata))
            ),
        ])

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
        let multipartSerializer = MultipartSerializer(boundary: boundary)
        let multipartForm: [UInt8] = try multipartSerializer.serialize(parts: [
            .init(
                headerFields: [
                    .contentDisposition: "form-data; name=\"source-archive\"",
                    .contentType: "application/zip",
                    .contentTransferEncoding: "binary ",
                ],
                body: packageArchive
            )
        ])

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
}

extension HTTPField.Name {
    static let contentTransferEncoding: Self = .init("Content-Transfer-Encoding")!
}
