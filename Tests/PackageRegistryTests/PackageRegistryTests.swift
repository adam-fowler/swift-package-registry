import HTTPTypes
import HummingbirdTesting
import NIOCore
@testable import PackageRegistry
import XCTest

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
            try await client.execute(uri: "registry/test/test", method: .get, headers: [.accept: "application/vnd.swift.registry.v200+json"]) { response in
                XCTAssertEqual(response.status, .badRequest)
                let problem = try JSONDecoder().decode(Problem.self, from: response.body)
                XCTAssertEqual(problem.type, ProblemType.unsupportedAcceptVersion.url)
            }
        }
    }

    func testUnsupportedMediaType() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "registry/test/test", method: .get, headers: [.accept: "application/vnd.swift.registry.v1+avi"]) { response in
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
}
