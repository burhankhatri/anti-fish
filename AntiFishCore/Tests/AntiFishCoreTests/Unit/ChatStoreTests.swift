import XCTest
@testable import AntiFishCore

final class ChatStoreTests: XCTestCase {
    func testMissingFileThrowsNotFound() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("nope.sqlite")
        XCTAssertThrowsError(try ChatStore(url: url)) { error in
            XCTAssertEqual(error as? SQLiteError, .notFound(url.path))
        }
    }

    func testOpensFixtureReadOnly() throws {
        let pair = try FixtureDB.standardPair()
        let store = try ChatStore(url: pair.chat)
        XCTAssertEqual(try store.db.scalarInt("SELECT COUNT(*) FROM ZWAMESSAGE"), 9)
        XCTAssertTrue(try store.tableExists("ZWAMEDIAITEM"))
        XCTAssertFalse(try store.tableExists("ZWANOPE"))
        XCTAssertThrowsError(try store.db.execute("CREATE TABLE t (x INTEGER)"))
    }

    func testSnapshotCopiesDatabaseWithSidecars() throws {
        let pair = try FixtureDB.standardPair()
        // A -wal sidecar must be copied under its exact name or SQLite silently drops recent rows.
        try Data("fake wal".utf8).write(to: URL(fileURLWithPath: pair.chat.path + "-wal"))
        let copy = try ChatStore.snapshot(of: pair.chat, into: try TestEnv.tempDir())
        XCTAssertEqual(copy.lastPathComponent, "ChatStorage.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path + "-wal"))
        try FileManager.default.removeItem(atPath: copy.path + "-wal")
        XCTAssertEqual(try ChatStore(url: copy).db.scalarInt("SELECT COUNT(*) FROM ZWAMESSAGE"), 9)
    }

    func testOpenWithRetriesReturnsWorkingStore() throws {
        let pair = try FixtureDB.standardPair()
        let store = try ChatStore.open(url: pair.chat)
        XCTAssertEqual(store.url, pair.chat)
        XCTAssertEqual(try store.db.scalarInt("SELECT COUNT(*) FROM ZWAMESSAGE"), 9)
    }

    func testOpenPropagatesNotFoundWithoutRetrying() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("absent.sqlite")
        XCTAssertThrowsError(try ChatStore.open(url: url)) { error in
            XCTAssertEqual(error as? SQLiteError, .notFound(url.path))
        }
    }
}
