import XCTest
@testable import AntiFishCore

final class ChatQueryTests: XCTestCase {
    private func store() throws -> ChatStore { try ChatStore(url: try FixtureDB.standardPair().chat) }

    // MARK: Chat list

    func testChatsComeBackNewestFirst() throws {
        let chats = try ChatListQuery.fetch(store())
        XCTAssertEqual(chats.map(\.jid), ["200@g.us", "111@lid", "333@lid"])
    }

    func testChatCarriesItsMetadata() throws {
        let chat = try XCTUnwrap(try ChatListQuery.fetch(store()).first { $0.jid == "111@lid" })
        XCTAssertEqual(chat.sessionPK, 1)
        XCTAssertEqual(chat.savedName, "Abdul Test")
        XCTAssertEqual(chat.unreadCount, 2)
        XCTAssertFalse(chat.isGroup)
        XCTAssertFalse(chat.isArchived)
        XCTAssertEqual(chat.lastMessageDate, Date(timeIntervalSinceReferenceDate: 800_000_700))
    }

    func testGroupChatsAreMarked() throws {
        let group = try XCTUnwrap(try ChatListQuery.fetch(store()).first { $0.jid == "200@g.us" })
        XCTAssertTrue(group.isGroup)
        XCTAssertEqual(group.savedName, "Family")
    }

    func testArchivedChatsAreMarkedButStillListed() throws {
        let archived = try XCTUnwrap(try ChatListQuery.fetch(store()).first { $0.jid == "333@lid" })
        XCTAssertTrue(archived.isArchived)
    }

    // MARK: Thread

    func testThreadIsOldestFirstAndCoversEveryType() throws {
        let messages = try MessageQuery.fetch(store(), sessionPK: 1)
        XCTAssertEqual(messages.map(\.messagePK), [1000, 1002, 1003, 1004, 1005, 1006, 1007])
    }

    func testTextMessageFields() throws {
        let text = try XCTUnwrap(try MessageQuery.fetch(store(), sessionPK: 1).first { $0.messagePK == 1005 })
        XCTAssertEqual(text.kind, .text)
        XCTAssertEqual(text.text, "hello there")
        XCTAssertFalse(text.isFromMe)
        XCTAssertEqual(text.senderJID, "111@lid")
        XCTAssertEqual(text.date, Date(timeIntervalSinceReferenceDate: 800_000_500))
    }

    func testOutgoingMessageIsMarked() throws {
        let mine = try XCTUnwrap(try MessageQuery.fetch(store(), sessionPK: 1).first { $0.messagePK == 1006 })
        XCTAssertTrue(mine.isFromMe)
        XCTAssertEqual(mine.text, "hi back")
        XCTAssertEqual(mine.senderJID, "")
    }

    func testVoiceNoteCarriesItsMediaAndDuration() throws {
        let note = try XCTUnwrap(try MessageQuery.fetch(store(), sessionPK: 1).first { $0.messagePK == 1000 })
        XCTAssertEqual(note.kind, .voiceNote)
        XCTAssertEqual(note.relativeMediaPath, "Media/111@lid/a/b/n1.opus")
        XCTAssertEqual(note.durationSeconds, 12)
    }

    func testMediaWithoutAFileIsStillListed() throws {
        let pending = try XCTUnwrap(try MessageQuery.fetch(store(), sessionPK: 1).first { $0.messagePK == 1002 })
        XCTAssertEqual(pending.kind, .voiceNote)
        XCTAssertNil(pending.relativeMediaPath)
    }

    func testOtherTypesAreLabelledNotDropped() throws {
        let messages = try MessageQuery.fetch(store(), sessionPK: 1)
        XCTAssertEqual(messages.first { $0.messagePK == 1004 }?.kind, .video)
        XCTAssertEqual(messages.first { $0.messagePK == 1007 }?.kind, .sticker)
    }

    func testGroupThreadAttributesTheSender() throws {
        let messages = try MessageQuery.fetch(store(), sessionPK: 2)
        XCTAssertEqual(messages.map(\.messagePK), [1001, 1008])
        XCTAssertTrue(messages.allSatisfy { $0.senderJID == "222@lid" })
    }

    func testKindMapping() {
        XCTAssertEqual(MessageKind(messageType: 0), .text)
        XCTAssertEqual(MessageKind(messageType: 1), .image)
        XCTAssertEqual(MessageKind(messageType: 2), .video)
        XCTAssertEqual(MessageKind(messageType: 3), .voiceNote)
        XCTAssertEqual(MessageKind(messageType: 6), .systemEvent)
        XCTAssertEqual(MessageKind(messageType: 7), .link)
        XCTAssertEqual(MessageKind(messageType: 8), .document)
        XCTAssertEqual(MessageKind(messageType: 11), .gif)
        XCTAssertEqual(MessageKind(messageType: 14), .deleted)
        XCTAssertEqual(MessageKind(messageType: 15), .sticker)
        XCTAssertEqual(MessageKind(messageType: 999), .other)
    }

    func testLimitReturnsTheMostRecentMessagesStillOldestFirst() throws {
        let messages = try MessageQuery.fetch(store(), sessionPK: 1, limit: 3)
        XCTAssertEqual(messages.map(\.messagePK), [1005, 1006, 1007])
    }
}
