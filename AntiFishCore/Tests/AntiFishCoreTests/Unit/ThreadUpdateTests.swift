import XCTest
@testable import AntiFishCore

/// Opening a chat checks up to thirty voice notes. Rebuilding the whole thread after each one
/// meant thirty full re-renders, and the scroll position was thrown away every time, so the list
/// could not be scrolled while it worked. One verdict should touch one row.
final class ThreadUpdateTests: XCTestCase {
    private func message(_ pk: Int64) -> ChatMessage {
        ChatMessage(messagePK: pk, kind: .voiceNote, text: nil, isFromMe: false, senderJID: "a@lid",
                    date: Date(timeIntervalSinceReferenceDate: Double(pk)), durationSeconds: 4,
                    relativeMediaPath: "Media/a/\(pk).opus")
    }

    private func verdict(_ pk: Int64) -> VerdictRecord {
        VerdictRecord(note: VoiceNoteRecord(messagePK: pk, chatJID: "a@lid", senderJID: "a@lid",
                                            isFromMe: false, date: Date(), durationSeconds: 4,
                                            relativeMediaPath: "Media/a/\(pk).opus", chatIsGroup: false),
                      verdict: Verdict(kind: .verified, colour: .green, comparedJID: "a@lid",
                                       score: 0.8, best: nil, reason: nil, explanation: "ok"),
                      speechSeconds: 4, computedAt: Date(), modelVersion: "m")
    }

    func testOneVerdictReplacesOnlyItsOwnRow() {
        let rows = [message(1), message(2), message(3)]
        let updated = ThreadUpdate.applying(verdict(2), to: rows.map { ($0, nil as VerdictRecord?) })
        XCTAssertNil(updated[0].1)
        XCTAssertEqual(updated[1].1?.messagePK, 2)
        XCTAssertNil(updated[2].1)
    }

    func testAVerdictForARowThatIsNotThereChangesNothing() {
        let rows = [message(1), message(2)].map { ($0, nil as VerdictRecord?) }
        let updated = ThreadUpdate.applying(verdict(99), to: rows)
        XCTAssertTrue(updated.allSatisfy { $0.1 == nil })
        XCTAssertEqual(updated.count, 2)
    }

    func testOrderIsPreserved() {
        let rows = [message(3), message(1), message(2)].map { ($0, nil as VerdictRecord?) }
        let updated = ThreadUpdate.applying(verdict(1), to: rows)
        XCTAssertEqual(updated.map { $0.0.messagePK }, [3, 1, 2])
    }

    /// The scroll should jump to the newest message when a different chat opens, and stay put
    /// while that chat is being checked.
    func testScrollOnlyFollowsAChatChange() {
        XCTAssertTrue(ThreadUpdate.shouldScrollToBottom(previousChat: nil, newChat: 1))
        XCTAssertTrue(ThreadUpdate.shouldScrollToBottom(previousChat: 1, newChat: 2))
        XCTAssertFalse(ThreadUpdate.shouldScrollToBottom(previousChat: 1, newChat: 1))
        XCTAssertFalse(ThreadUpdate.shouldScrollToBottom(previousChat: 2, newChat: nil))
    }
}
