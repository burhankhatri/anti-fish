import XCTest
@testable import AntiFishCore

final class StoreActionsTests: XCTestCase {
    private func db(withContact jid: String = "a@lid") throws -> AppDatabase {
        let db = try AppDatabase(url: nil)
        try db.saveContacts([ContactRecord(jid: jid, displayName: "Abdul", isSaved: true,
                                           pinned: false, blacklisted: false, avatarPath: nil)])
        return db
    }

    func testPinAndBlacklistFlags() throws {
        let db = try db()
        try db.setPinned(jid: "a@lid", true)
        try db.setBlacklisted(jid: "a@lid", true)
        let c = try XCTUnwrap(try db.contact(jid: "a@lid"))
        XCTAssertTrue(c.pinned)
        XCTAssertTrue(c.blacklisted)
        XCTAssertEqual(c.displayName, "Abdul", "flags must not disturb the rest of the row")
    }

    func testFlagsOnAnUnknownContactAreIgnored() throws {
        let db = try db()
        try db.setPinned(jid: "ghost@lid", true)
        XCTAssertNil(try db.contact(jid: "ghost@lid"))
    }

    func testOverridingAVerdict() throws {
        let db = try db()
        let note = VoiceNoteRecord(messagePK: 6, chatJID: "x@lid", senderJID: "x@lid", isFromMe: false,
                                   date: Date(), durationSeconds: 4, relativeMediaPath: "Media/x.opus",
                                   chatIsGroup: false)
        let grey = Verdict(kind: .unknownVoice, colour: .grey, comparedJID: nil, score: nil,
                           best: nil, reason: nil, explanation: "unknown")
        try db.saveVerdict(VerdictRecord(note: note, verdict: grey, speechSeconds: 3,
                                         computedAt: Date(), modelVersion: "m"))
        try db.overrideVerdict(messagePK: 6, kind: .impersonationSuspected, colour: .red,
                               reason: "userReported", explanation: "You reported this sender.")
        let v = try XCTUnwrap(try db.verdict(messagePK: 6))
        XCTAssertEqual(v.kind, "impersonationSuspected")
        XCTAssertEqual(v.colour, "red")
        XCTAssertEqual(v.reason, "userReported")
        XCTAssertEqual(v.explanation, "You reported this sender.")
        XCTAssertEqual(v.senderJID, "x@lid", "the note it describes is unchanged")
    }
}
