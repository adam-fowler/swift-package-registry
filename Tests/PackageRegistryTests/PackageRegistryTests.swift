import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdAuthTesting
import HummingbirdCore
import HummingbirdTesting
import NIOCore
import XCTest
import ZipArchive
import _NIOFileSystem

@testable import PackageRegistry
@testable import PackageRegistryLibrary

struct Problem: Error, Decodable {
    let type: String?
    let detail: String?
    let title: String?
    let instance: String?
}

final class PackageRegistryTests: XCTestCase {
    struct TestArguments: AppArguments {
        var hostname: String { "localhost" }
        var port: Int { 8081 }
        var inMemory = true
        var revert = false
        var migrate = true
    }

    func testNoAcceptHeader() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "registry/test/test", method: .get) { response in
                XCTAssertEqual(response.status, .badRequest)
                let problem = try JSONDecoder().decode(Problem.self, from: response.body)
                XCTAssertEqual(problem.type, ProblemType.noAcceptHeader.url)
                XCTAssertEqual(response.headers[.contentVersion], "1")
                XCTAssertEqual(response.headers[.contentType], "application/problem+json")
            }
        }
    }

    func testInvalidAcceptHeader() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "registry/test/test", method: .get, headers: [.accept: "application/json"]) { response in
                XCTAssertEqual(response.status, .notAcceptable)
                let problem = try JSONDecoder().decode(Problem.self, from: response.body)
                XCTAssertEqual(problem.type, ProblemType.invalidAcceptHeader.url)
            }
        }
    }

    func testUnsupportedAcceptVersionHeader() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "registry/test/test", method: .get, headers: [.accept: "application/vnd.swift.registry.v200+json"]) {
                response in
                XCTAssertEqual(response.status, .badRequest)
                let problem = try JSONDecoder().decode(Problem.self, from: response.body)
                XCTAssertEqual(problem.type, ProblemType.unsupportedAcceptVersion.url)
            }
        }
    }

    func testUnsupportedMediaType() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "registry/test/test", method: .get, headers: [.accept: "application/vnd.swift.registry.v1+avi"]) {
                response in
                XCTAssertEqual(response.status, .notAcceptable)
                let problem = try JSONDecoder().decode(Problem.self, from: response.body)
                XCTAssertEqual(problem.type, ProblemType.invalidAcceptHeader.url)
                XCTAssertEqual(response.headers[.contentVersion], "1")
            }
        }
    }

    func testVersion() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "registry/test/test", method: .get, headers: [.accept: "application/vnd.swift.registry.v1"]) { response in
                XCTAssertEqual(response.status, .notFound)
                XCTAssertEqual(response.headers[.contentVersion], "1")
            }
        }
    }

    static func uploadTestPackage(_ client: some TestClientProtocol, buffer: ByteBuffer, version: String = "1.0.0") async throws -> TestResponse {
        try await client.execute(
            uri: "registry/test/test-package/\(version)",
            method: .put,
            headers: [
                .accept: "application/vnd.swift.registry.v1",
                .contentType: "multipart/form-data;boundary=6E39719F-594A-4428-A9C1-DE8151644915",
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
            switch response.status {
            case .movedPermanently:
                return response
            case .accepted:
                break
            default:
                throw Problem(type: response.status.description, detail: "Unexpected status", title: nil, instance: nil)
            }
        }
    }

    func testUploadVersion() async throws {
        let appArgs = TestArguments()
        let app = try await buildApplication(appArgs)
        let filePath = Bundle.module.path(forResource: "test-package", ofType: "bin")!
        let testPackageBuffer = try await FileSystem.shared.withFileHandle(forReadingAt: .init(filePath)) { reader in
            try await reader.readToEnd(maximumSizeAllowed: .unlimited)
        }
        try await app.test(.router) { client in
            let response = try await Self.uploadTestPackage(client, buffer: testPackageBuffer)
            XCTAssertEqual(response.status, .accepted)
            XCTAssertNotNil(response.headers[.retryAfter])
            let location = try XCTUnwrap(response.headers[.location])

            let waitResponse = try await Self.waitForPackageToBeProcessed(client, location: location)
            XCTAssertEqual(waitResponse.headers[.location], "https://\(appArgs.hostname):\(appArgs.port)/registry/test/test-package/1.0.0")
        }
    }

    func testUploadProcessingVersion() async throws {
        let appArgs = TestArguments()
        let app = try await buildApplication(appArgs)
        let filePath = Bundle.module.path(forResource: "test-package", ofType: "bin")!
        let testPackageBuffer = try await FileSystem.shared.withFileHandle(forReadingAt: .init(filePath)) { reader in
            try await reader.readToEnd(maximumSizeAllowed: .unlimited)
        }
        try await app.test(.router) { client in
            let response = try await Self.uploadTestPackage(client, buffer: testPackageBuffer)
            XCTAssertEqual(response.status, .accepted)
            XCTAssertNotNil(response.headers[.retryAfter])
            XCTAssertNotNil(response.headers[.location])

            let response2 = try await Self.uploadTestPackage(client, buffer: testPackageBuffer)
            XCTAssertEqual(response2.status, .conflict)
            let problem = try JSONDecoder().decode(Problem.self, from: response2.body)
            XCTAssertEqual(problem.type, ProblemType.versionAlreadyExists.url)
        }
    }

    /// Upload package and test all endpoints referencing it work
    func testUploadedPackage() async throws {
        struct Releases: Codable {
            struct Release: Codable {
                let url: String
            }
            let releases: [String: Release]
        }
        struct Metadata: Codable {
            struct Release: Codable {
                let url: String
            }
            let releases: [String: Release]
        }
        let appArgs = TestArguments()
        let app = try await buildApplication(appArgs)
        let filePath = Bundle.module.path(forResource: "test-package", ofType: "bin")!
        let testPackageBuffer = try await FileSystem.shared.withFileHandle(forReadingAt: .init(filePath)) { reader in
            try await reader.readToEnd(maximumSizeAllowed: .unlimited)
        }
        try await app.test(.router) { client in
            // upload package
            let response = try await Self.uploadTestPackage(client, buffer: testPackageBuffer, version: "0.1.0")
            XCTAssertEqual(response.status, .accepted)
            XCTAssertNotNil(response.headers[.retryAfter])
            let location = try XCTUnwrap(response.headers[.location])

            // wait for it to have been processed
            let waitResponse = try await Self.waitForPackageToBeProcessed(client, location: location)
            XCTAssertEqual(waitResponse.headers[.location], "https://\(appArgs.hostname):\(appArgs.port)/registry/test/test-package/0.1.0")

            // test release list
            try await client.execute(
                uri: "/registry/test/test-package",
                method: .get,
                headers: [.accept: "application/vnd.swift.registry.v1"]
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let releases = try JSONDecoder().decode(Releases.self, from: response.body)
                XCTAssertEqual(releases.releases["0.1.0"]?.url, "https://\(appArgs.hostname):\(appArgs.port)/registry/test/test-package/0.1.0")
            }

            // test download of zip
            try await client.execute(
                uri: "/registry/test/test-package/0.1.0.zip",
                method: .get,
                headers: [.accept: "application/vnd.swift.registry.v1"]
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let zipReader = try ZipArchiveReader(buffer: response.body.readableBytesView)
                let directory = try zipReader.readDirectory()
                XCTAssertNotNil(directory.first { $0.filename == "test.test-package/Package.swift" })
            }

            // test metadata
            try await client.execute(
                uri: "/registry/test/test-package/0.1.0",
                method: .get,
                headers: [.accept: "application/vnd.swift.registry.v1"]
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let release = try JSONDecoder().decode(PackageRelease.self, from: response.body)
                XCTAssertEqual(release.id, try .init("test.test-package"))
                XCTAssertEqual(release.version, "0.1.0")
                XCTAssertEqual(release.metadata?.author?.name, "Joe Bloggs")
                XCTAssertEqual(release.metadata?.description, "Test package")
            }

            // test package identifiers
            try await client.execute(
                uri: "/registry/identifiers?url=https://github.com/test/test-package.git",
                method: .get,
                headers: [.accept: "application/vnd.swift.registry.v1"]
            ) { response in
                struct Identifiers: Codable {
                    let identifiers: [PackageIdentifier]
                }
                XCTAssertEqual(response.status, .ok)
                let identifiers = try JSONDecoder().decode(Identifiers.self, from: response.body)
                XCTAssertEqual(identifiers.identifiers.first, try .init("test.test-package"))
            }
        }
    }
}
