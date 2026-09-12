import XCTest
@testable import AntiFishCore

final class VoiceNoteQueryIntegrationTests: XCTestCase {
    func testLiveQueryReturnsIncomingNotesWithFilesOnDisk() throws {
        try TestEnv.skipUnlessRealWA()
        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store)
        XCTAssertGreaterThan(notes.count, 0)
        XCTAssertTrue(notes.allSatisfy { $0.relativeMediaPath.hasPrefix("Message/Media/") })
        let incomingOnDisk = notes.filter {
            !$0.isFromMe && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: $0.relativeMediaPath).path)
        }
        XCTAssertGreaterThan(incomingOnDisk.count, 0)
        XCTAssertTrue(incomingOnDisk.allSatisfy { !$0.senderJID.isEmpty })
        // Voice notes are short spoken clips, not hour-long files.
        XCTAssertTrue(incomingOnDisk.allSatisfy { $0.durationSeconds >= 0 && $0.durationSeconds < 3600 })
    }
}
