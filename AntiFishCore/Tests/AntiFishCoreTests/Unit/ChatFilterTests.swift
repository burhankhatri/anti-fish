import XCTest
@testable import AntiFishCore

/// Groups and one-to-one chats answer different questions. Mixing them means scrolling past
/// twenty group threads to find the person who just sent you a voice note.
final class ChatFilterTests: XCTestCase {
    private func chat(_ jid: String, group: Bool) -> ChatSummary {
        ChatSummary(sessionPK: Int64(jid.count), jid: jid, savedName: jid, isGroup: group,
                    isArchived: false, unreadCount: 0, lastMessageDate: Date(),
                    voiceNoteCount: 1, voiceNoteTotal: 1)
    }

    private var mixed: [ChatSummary] {
        [chat("a@lid", group: false), chat("bb@g.us", group: true),
         chat("ccc@lid", group: false), chat("dddd@g.us", group: true)]
    }

    func testEveryoneShowsBoth() {
        XCTAssertEqual(ChatFilter.everyone.apply(to: mixed).count, 4)
    }

    func testPeopleShowsOnlyOneToOneChats() {
        let people = ChatFilter.people.apply(to: mixed)
        XCTAssertEqual(people.count, 2)
        XCTAssertTrue(people.allSatisfy { !$0.isGroup })
    }

    func testGroupsShowsOnlyGroups() {
        let groups = ChatFilter.groups.apply(to: mixed)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy(\.isGroup))
    }

    func testEveryFilterHasAName() {
        for filter in ChatFilter.allCases {
            XCTAssertFalse(filter.title.isEmpty)
            XCTAssertFalse(filter.title.contains("_"))
        }
    }

    func testFilteringAnEmptyListIsSafe() {
        for filter in ChatFilter.allCases {
            XCTAssertTrue(filter.apply(to: []).isEmpty)
        }
    }
}
