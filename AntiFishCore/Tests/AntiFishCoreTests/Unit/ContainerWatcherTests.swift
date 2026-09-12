import XCTest
@testable import AntiFishCore

final class ContainerWatcherTests: XCTestCase {
    func testOnlyVoiceNotesAndTheMessageDatabaseAreRelevant() {
        XCTAssertTrue(ContainerWatcher.isRelevant("/c/Message/Media/111@lid/a/b/x.opus"))
        XCTAssertTrue(ContainerWatcher.isRelevant("/c/Message/Media/111@lid/a/b/x.M4A"))
        XCTAssertTrue(ContainerWatcher.isRelevant("/c/ChatStorage.sqlite-wal"))
        XCTAssertTrue(ContainerWatcher.isRelevant("/c/ChatStorage.sqlite"))
        XCTAssertFalse(ContainerWatcher.isRelevant("/c/Message/Media/111@lid/a/b/x.jpg"))
        XCTAssertFalse(ContainerWatcher.isRelevant("/c/Message/Media/Profile/x.opus"))
        XCTAssertFalse(ContainerWatcher.isRelevant("/c/ContactsV2.sqlite-wal"))
        XCTAssertFalse(ContainerWatcher.isRelevant("/c/Axolotl.sqlite-wal"))
    }

    func testFiresOnceForANewVoiceNote() throws {
        let root = try TestEnv.tempDir()
        let dir = root.appendingPathComponent("Message/Media/111@lid/a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fired = expectation(description: "watcher fired")
        fired.assertForOverFulfill = false
        let watcher = ContainerWatcher(root: root, debounce: 0.3, pollInterval: 3600) { fired.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.6)   // let the stream attach before writing
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("n.opus"))
        wait(for: [fired], timeout: 10)
    }

    func testIgnoresFilesThatAreNotVoiceNotes() throws {
        let root = try TestEnv.tempDir()
        let dir = root.appendingPathComponent("Message/Media/111@lid/a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fired = expectation(description: "should not fire")
        fired.isInverted = true
        let watcher = ContainerWatcher(root: root, debounce: 0.3, pollInterval: 3600) { fired.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.6)
        try Data([1]).write(to: dir.appendingPathComponent("thumb.jpg"))
        wait(for: [fired], timeout: 3)
    }

    func testStartAndStopAreIdempotent() throws {
        let watcher = ContainerWatcher(root: try TestEnv.tempDir(), debounce: 0.1, pollInterval: 3600) {}
        watcher.start()
        watcher.start()
        watcher.stop()
        watcher.stop()
    }
}
