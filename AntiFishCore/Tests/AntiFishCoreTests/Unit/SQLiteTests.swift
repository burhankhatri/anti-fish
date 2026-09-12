import XCTest
@testable import AntiFishCore

final class SQLiteTests: XCTestCase {

    // MARK: Opening

    func testMissingFileThrowsNotFound() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("nope.sqlite")
        XCTAssertThrowsError(try SQLiteDatabase(url: url, readOnly: true)) { error in
            XCTAssertEqual(error as? SQLiteError, .notFound(url.path))
        }
    }

    func testInMemoryDatabaseWorks() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.execute("CREATE TABLE t (a INTEGER)")
        try db.run("INSERT INTO t VALUES (?)", [.int(7)])
        XCTAssertEqual(try db.query("SELECT a FROM t").first?.int("a"), 7)
    }

    func testReadWriteCreatesFileAndPersists() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("nested/store.sqlite")
        let db = try SQLiteDatabase(url: url, readOnly: false)
        try db.execute("CREATE TABLE t (a TEXT)")
        try db.run("INSERT INTO t VALUES (?)", [.text("hi")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reopened = try SQLiteDatabase(url: url, readOnly: true)
        XCTAssertEqual(try reopened.query("SELECT a FROM t").first?.string("a"), "hi")
    }

    func testReadOnlyRefusesWrites() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("ro.sqlite")
        try SQLiteDatabase(url: url, readOnly: false).execute("CREATE TABLE t (a INTEGER)")
        let db = try SQLiteDatabase(url: url, readOnly: true)
        XCTAssertThrowsError(try db.execute("CREATE TABLE other (b INTEGER)"))
        XCTAssertThrowsError(try db.run("INSERT INTO t VALUES (?)", [.int(1)]))
    }

    // MARK: Values and typed reads

    func testAllValueTypesRoundTrip() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.execute("CREATE TABLE t (i INTEGER, d REAL, s TEXT, b BLOB, n INTEGER)")
        try db.run("INSERT INTO t VALUES (?, ?, ?, ?, ?)",
                   [.int(42), .double(1.5), .text("abc"), .blob(Data([1, 2, 3])), .null])
        let row = try XCTUnwrap(try db.query("SELECT * FROM t").first)
        XCTAssertEqual(row.int("i"), 42)
        XCTAssertEqual(row.double("d"), 1.5)
        XCTAssertEqual(row.string("s"), "abc")
        XCTAssertEqual(row.data("b"), Data([1, 2, 3]))
        XCTAssertNil(row.int("n"))
        XCTAssertNil(row.string("n"))
        XCTAssertNil(row.data("n"))
        XCTAssertNil(row.double("n"))
    }

    func testMissingColumnReadsAsNil() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.execute("CREATE TABLE t (a INTEGER)")
        try db.run("INSERT INTO t VALUES (1)")
        let row = try XCTUnwrap(try db.query("SELECT a FROM t").first)
        XCTAssertNil(row.int("nosuch"))
        XCTAssertNil(row.string("nosuch"))
    }

    func testBoolAndIntegerCoercion() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.execute("CREATE TABLE t (flag INTEGER, num REAL)")
        try db.run("INSERT INTO t VALUES (1, 3)")
        let row = try XCTUnwrap(try db.query("SELECT * FROM t").first)
        XCTAssertEqual(row.bool("flag"), true)
        // A REAL column still reads as an integer; WhatsApp stores timestamps both ways.
        XCTAssertEqual(row.int("num"), 3)
        XCTAssertEqual(row.double("num"), 3)
    }

    func testNamedArguments() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.execute("CREATE TABLE t (a INTEGER, b TEXT)")
        try db.run("INSERT INTO t VALUES (1, 'x'), (2, 'y'), (3, 'z')")
        let rows = try db.query("SELECT b FROM t WHERE a > :min ORDER BY a", named: ["min": .int(1)])
        XCTAssertEqual(rows.compactMap { $0.string("b") }, ["y", "z"])
    }

    func testScalarHelpers() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.execute("CREATE TABLE t (a INTEGER)")
        try db.run("INSERT INTO t VALUES (5), (9)")
        XCTAssertEqual(try db.scalarInt("SELECT MAX(a) FROM t"), 9)
        XCTAssertEqual(try db.scalarInt("SELECT MAX(a) FROM t WHERE a > 100"), nil)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM t"), 2)
    }

    // MARK: Schema and migrations

    func testTableExists() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.execute("CREATE TABLE present (a INTEGER)")
        XCTAssertTrue(try db.tableExists("present"))
        XCTAssertFalse(try db.tableExists("absent"))
    }

    func testMigrationsRunOnceInOrder() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("m.sqlite")
        let migrations: [(String, (SQLiteDatabase) throws -> Void)] = [
            ("v1", { try $0.execute("CREATE TABLE a (x INTEGER)") }),
            ("v2", { try $0.execute("CREATE TABLE b (y INTEGER)") }),
        ]
        let db = try SQLiteDatabase(url: url, readOnly: false)
        try db.migrate(migrations)
        XCTAssertEqual(db.userVersion, 2)
        XCTAssertTrue(try db.tableExists("a"))
        XCTAssertTrue(try db.tableExists("b"))
        // Re-running is a no-op rather than an error.
        try db.migrate(migrations)
        XCTAssertEqual(db.userVersion, 2)
        // A later migration applies on top without repeating the earlier ones.
        try db.migrate(migrations + [("v3", { try $0.execute("CREATE TABLE c (z INTEGER)") })])
        XCTAssertEqual(db.userVersion, 3)
        XCTAssertTrue(try db.tableExists("c"))
    }

    func testFailedMigrationRollsBackAndKeepsVersion() throws {
        let db = try SQLiteDatabase.inMemory()
        let bad: [(String, (SQLiteDatabase) throws -> Void)] = [
            ("v1", { try $0.execute("CREATE TABLE ok (x INTEGER)") }),
            ("v2", { try $0.execute("THIS IS NOT SQL") }),
        ]
        XCTAssertThrowsError(try db.migrate(bad))
        XCTAssertEqual(db.userVersion, 1)
        XCTAssertTrue(try db.tableExists("ok"))
    }

    func testTransactionRollsBackOnError() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.execute("CREATE TABLE t (a INTEGER)")
        struct Boom: Error {}
        XCTAssertThrowsError(try db.transaction {
            try db.run("INSERT INTO t VALUES (1)")
            throw Boom()
        })
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM t"), 0)
        try db.transaction { try db.run("INSERT INTO t VALUES (2)") }
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM t"), 1)
    }

    func testBadSQLThrowsWithMessage() throws {
        let db = try SQLiteDatabase.inMemory()
        XCTAssertThrowsError(try db.query("SELECT * FROM nope")) { error in
            guard case .prepare(let message)? = error as? SQLiteError else {
                return XCTFail("expected .prepare, got \(error)")
            }
            XCTAssertTrue(message.contains("nope"), message)
        }
    }
}
