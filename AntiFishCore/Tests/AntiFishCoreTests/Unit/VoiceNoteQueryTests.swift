import XCTest
@testable import AntiFishCore

final class VoiceNoteQueryTests: XCTestCase {
    private func store() throws -> ChatStore { try ChatStore(url: try FixtureDB.standardPair().chat) }

    func testReturnsOnlyVoiceNoteRowsThatHaveAFile() throws {
        // Type 3 is a voice note; type 2 is video. Row 1002 has no local media path yet.
        XCTAssertEqual(try VoiceNoteQuery.fetch(store()).map(\.messagePK), [1000, 1001, 1003])
    }

    func testOneToOneIncomingNoteFields() throws {
        let note = try XCTUnwrap(try VoiceNoteQuery.fetch(store()).first)
        XCTAssertEqual(note.chatJID, "111@lid")
        XCTAssertEqual(note.senderJID, "111@lid")
        XCTAssertFalse(note.isFromMe)
        XCTAssertFalse(note.chatIsGroup)
        XCTAssertEqual(note.durationSeconds, 12)
        XCTAssertEqual(note.relativeMediaPath, "Media/111@lid/a/b/n1.opus")
        XCTAssertEqual(note.date, Date(timeIntervalSinceReferenceDate: 800_000_000))
    }

    func testGroupNoteAttributesSenderToTheMember() throws {
        let note = try VoiceNoteQuery.fetch(store())[1]
        XCTAssertTrue(note.chatIsGroup)
        XCTAssertEqual(note.chatJID, "200@g.us")
        XCTAssertEqual(note.senderJID, "222@lid")
    }

    func testOutgoingNoteHasNoSender() throws {
        let note = try VoiceNoteQuery.fetch(store())[2]
        XCTAssertTrue(note.isFromMe)
        XCTAssertEqual(note.senderJID, "")
        XCTAssertEqual(note.chatJID, "111@lid")
    }

    func testAfterPKIsIncremental() throws {
        let s = try store()
        XCTAssertEqual(try VoiceNoteQuery.fetch(s, afterPK: 1000).map(\.messagePK), [1001, 1003])
        XCTAssertEqual(try VoiceNoteQuery.fetch(s, afterPK: 9999).count, 0)
        XCTAssertEqual(try VoiceNoteQuery.maxMessagePK(s), 1004)
    }

    func testPendingFloorFindsOldestUndownloadedIncomingNote() throws {
        let s = try store()
        XCTAssertEqual(try VoiceNoteQuery.pendingFloor(s, since: Date(timeIntervalSinceReferenceDate: 0)), 1002)
        XCTAssertNil(try VoiceNoteQuery.pendingFloor(s, since: Date(timeIntervalSinceReferenceDate: 900_000_000)))
    }
}
