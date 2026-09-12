import XCTest
@testable import AntiFishCore

final class ChatOrderingTests: XCTestCase {
    private func store() throws -> ChatStore { try ChatStore(url: try FixtureDB.standardPair().chat) }

    /// Demoing the product means finding the chats that actually have voice in them, so the list
    /// can be ordered by how much evidence each chat carries rather than by recency.
    func testEachChatKnowsHowMuchVoiceItHas() throws {
        let chats = try ChatListQuery.fetch(store())
        let oneToOne = try XCTUnwrap(chats.first { $0.jid == "111@lid" })
        let group = try XCTUnwrap(chats.first { $0.jid == "200@g.us" })
        let quiet = try XCTUnwrap(chats.first { $0.jid == "333@lid" })
        // Session 1 has three incoming voice notes (1000, 1002) plus one outgoing (1003).
        XCTAssertEqual(oneToOne.voiceNoteCount, 2, "only notes from other people count as evidence")
        XCTAssertEqual(group.voiceNoteCount, 1)
        XCTAssertEqual(quiet.voiceNoteCount, 0)
    }

    func testSortingByEvidencePutsTheLoudestChatsFirst() throws {
        let chats = try ChatListQuery.fetch(store())
        XCTAssertEqual(ChatOrder.mostVoice.apply(to: chats).map(\.jid),
                       ["111@lid", "200@g.us", "333@lid"])
    }

    func testSortingByRecencyIsUnchanged() throws {
        let chats = try ChatListQuery.fetch(store())
        XCTAssertEqual(ChatOrder.recent.apply(to: chats).map(\.jid),
                       ["200@g.us", "111@lid", "333@lid"])
    }

    func testEvidenceOrderBreaksTiesByRecency() {
        let old = ChatSummary(sessionPK: 1, jid: "a", savedName: nil, isGroup: false, isArchived: false,
                              unreadCount: 0, lastMessageDate: Date(timeIntervalSinceReferenceDate: 1),
                              voiceNoteCount: 4)
        let new = ChatSummary(sessionPK: 2, jid: "b", savedName: nil, isGroup: false, isArchived: false,
                              unreadCount: 0, lastMessageDate: Date(timeIntervalSinceReferenceDate: 2),
                              voiceNoteCount: 4)
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
