import Logging
@testable import PackageRegistry
@_spi(ConnectionPool) import PostgresNIO
import XCTest

final class MigrationTests: XCTestCase {
    struct TestMigration1: Migration {
        func migrate(connection: PostgresConnection, logger: Logger) async throws {}
        func revert(connection: PostgresConnection, logger: Logger) async throws {}
    }

    struct TestMigration2: Migration {
        func migrate(connection: PostgresConnection, logger: Logger) async throws {}
        func revert(connection: PostgresConnection, logger: Logger) async throws {}
    }

    struct TestMigration3: Migration {
        func migrate(connection: PostgresConnection, logger: Logger) async throws {}
        func revert(connection: PostgresConnection, logger: Logger) async throws {}
    }

    struct TestMigration4: Migration {
        func migrate(connection: PostgresConnection, logger: Logger) async throws {}
        func revert(connection: PostgresConnection, logger: Logger) async throws {}
    }

    let logger = Logger(label: "MigrationTests")

    func testMigrate() async throws {
        let repository = MemoryMigrationRepository()
        let migrations = Migrations(repository: repository)
        await migrations.add(TestMigration1())
        await migrations.add(TestMigration2())
        try await migrations.migrate(logger: self.logger, dryRun: false)
        XCTAssertEqual(repository.migrations.count, 2)
        XCTAssertEqual(repository.migrations[0].name, "TestMigration1")
        XCTAssertEqual(repository.migrations[1].name, "TestMigration2")
    }

    func testRevert() async throws {
        let repository = MemoryMigrationRepository()
        let migrations = Migrations(repository: repository)
        await migrations.add(TestMigration1())
        await migrations.add(TestMigration2())
        try await migrations.migrate(logger: self.logger, dryRun: false)
        try await migrations.revert(logger: self.logger, dryRun: false)
        XCTAssertEqual(repository.migrations.count, 0)
    }

    func testSecondMigrate() async throws {
        let repository = MemoryMigrationRepository()
        let migrations = Migrations(repository: repository)
        await migrations.add(TestMigration1())
        await migrations.add(TestMigration2())
        try await migrations.migrate(logger: self.logger, dryRun: false)
        await migrations.add(TestMigration3())
        await migrations.add(TestMigration4())
        try await migrations.migrate(logger: self.logger, dryRun: false)
        XCTAssertEqual(repository.migrations.count, 4)
        XCTAssertEqual(repository.migrations[0].name, "TestMigration1")
        XCTAssertEqual(repository.migrations[1].name, "TestMigration2")
        XCTAssertEqual(repository.migrations[2].name, "TestMigration3")
        XCTAssertEqual(repository.migrations[3].name, "TestMigration4")
    }

    func testRemoveMigration() async throws {
        let repository = MemoryMigrationRepository()
        let migrations = Migrations(repository: repository)
        await migrations.add(TestMigration1())
        await migrations.add(TestMigration2())
        await migrations.add(TestMigration3())
        try await migrations.migrate(logger: self.logger, dryRun: false)
        let migrations2 = Migrations(repository: repository)
        await migrations2.add(TestMigration1())
        await migrations2.add(TestMigration2())
        await migrations2.add(revert: TestMigration3())
        try await migrations2.migrate(logger: self.logger, dryRun: false)
        XCTAssertEqual(repository.migrations.count, 2)
        XCTAssertEqual(repository.migrations[0].name, "TestMigration1")
        XCTAssertEqual(repository.migrations[1].name, "TestMigration2")
    }

    func testReplaceMigration() async throws {
        let repository = MemoryMigrationRepository()
        let migrations = Migrations(repository: repository)
        await migrations.add(TestMigration1())
        await migrations.add(TestMigration2())
        await migrations.add(TestMigration3())
        try await migrations.migrate(logger: self.logger, dryRun: false)
        let migrations2 = Migrations(repository: repository)
        await migrations2.add(TestMigration1())
        await migrations2.add(TestMigration2())
        await migrations2.add(TestMigration4())
        await migrations2.add(revert: TestMigration3())
        try await migrations2.migrate(logger: self.logger, dryRun: false)
        XCTAssertEqual(repository.migrations.count, 3)
        XCTAssertEqual(repository.migrations[0].name, "TestMigration1")
        XCTAssertEqual(repository.migrations[1].name, "TestMigration2")
        XCTAssertEqual(repository.migrations[2].name, "TestMigration4")
    }
}
