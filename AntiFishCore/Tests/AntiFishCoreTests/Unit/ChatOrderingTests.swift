import XCTest
@testable import AntiFishCore

final class ChatOrderingTests: XCTestCase {
    private func store() throws -> ChatStore { try ChatStore(url: try FixtureDB.standardPair().chat) }

    /// Only 7% of the voice notes in a real WhatsApp database have their audio on this Mac:
    /// WhatsApp Desktop downloads media from the day it was linked, not the whole history.
    /// A chat's evidence is therefore what can actually be played, not what the database lists.
    func testChatEvidenceCountsOnlyPlayableNotes() throws {
        let chats = try ChatListQuery.fetch(store())
        let oneToOne = try XCTUnwrap(chats.first { $0.jid == "111@lid" })
        let group = try XCTUnwrap(chats.first { $0.jid == "200@g.us" })
        let quiet = try XCTUnwrap(chats.first { $0.jid == "333@lid" })
        // Session 1 has two incoming voice notes: 1000 has audio, 1002 has not downloaded.
        XCTAssertEqual(oneToOne.voiceNoteCount, 1, "a note with no audio is not evidence")
        XCTAssertEqual(oneToOne.voiceNoteTotal, 2, "but the app still knows it exists")
        XCTAssertEqual(group.voiceNoteCount, 1)
        XCTAssertEqual(group.voiceNoteTotal, 1)
        XCTAssertEqual(quiet.voiceNoteCount, 0)
        XCTAssertEqual(quiet.voiceNoteTotal, 0)
    }

    func testAChatWithNoPlayableAudioSortsBelowOneWithSome() {
        let loud = ChatSummary(sessionPK: 1, jid: "loud", savedName: nil, isGroup: false, isArchived: false,
                               unreadCount: 0, lastMessageDate: Date(timeIntervalSinceReferenceDate: 1),
                               voiceNoteCount: 3, voiceNoteTotal: 5)
        // 400 notes in the database, none of them downloaded: nothing to demo here.
        let empty = ChatSummary(sessionPK: 2, jid: "empty", savedName: nil, isGroup: false, isArchived: false,
                                unreadCount: 0, lastMessageDate: Date(timeIntervalSinceReferenceDate: 2),
                                voiceNoteCount: 0, voiceNoteTotal: 400)
        XCTAssertEqual(ChatOrder.mostVoice.apply(to: [empty, loud]).map(\.jid), ["loud", "empty"])
    }

    func testSortingByEvidencePutsTheLoudestChatsFirst() throws {
        let ordered = ChatOrder.mostVoice.apply(to: try ChatListQuery.fetch(store()))
        XCTAssertEqual(ordered.map(\.voiceNoteCount), [1, 1, 0], "playable counts descend")
        XCTAssertEqual(ordered.last?.jid, "333@lid", "the chat with nothing to play comes last")
    }

    func testSortingByRecencyIsUnchanged() throws {
        let chats = try ChatListQuery.fetch(store())
        XCTAssertEqual(ChatOrder.recent.apply(to: chats).map(\.jid),
                       ["200@g.us", "111@lid", "333@lid"])
    }

    func testEvidenceOrderBreaksTiesByRecency() {
        let old = ChatSummary(sessionPK: 1, jid: "a", savedName: nil, isGroup: false, isArchived: false,
                              unreadCount: 0, lastMessageDate: Date(timeIntervalSinceReferenceDate: 1),
                              voiceNoteCount: 4, voiceNoteTotal: 4)
        let new = ChatSummary(sessionPK: 2, jid: "b", savedName: nil, isGroup: false, isArchived: false,
                              unreadCount: 0, lastMessageDate: Date(timeIntervalSinceReferenceDate: 2),
                              voiceNoteCount: 4, voiceNoteTotal: 4)
        XCTAssertEqual(ChatOrder.mostVoice.apply(to: [old, new]).map(\.jid), ["b", "a"])
    }

    // MARK: Hiding

    func testHiddenChatsRoundTripAndAreReported() throws {
        let db = try AppDatabase(url: nil)
        XCTAssertTrue(try db.hiddenChatJIDs().isEmpty)
        try db.setChatHidden(jid: "200@g.us", true)
        try db.setChatHidden(jid: "333@lid", true)
        XCTAssertEqual(try db.hiddenChatJIDs(), ["200@g.us", "333@lid"])
        try db.setChatHidden(jid: "200@g.us", false)
        XCTAssertEqual(try db.hiddenChatJIDs(), ["333@lid"])
    }

    func testHidingTheSameChatTwiceDoesNotDuplicateIt() throws {
        let db = try AppDatabase(url: nil)
        try db.setChatHidden(jid: "a@lid", true)
        try db.setChatHidden(jid: "a@lid", true)
        XCTAssertEqual(try db.hiddenChatJIDs(), ["a@lid"])
    }

    func testUnhidingSomethingThatWasNeverHiddenIsSafe() throws {
        let db = try AppDatabase(url: nil)
        try db.setChatHidden(jid: "ghost@lid", false)
        XCTAssertTrue(try db.hiddenChatJIDs().isEmpty)
    }
}
