import XCTest
import AntiFishCore
@testable import AntiFish

/// A thread that renders an empty bubble for every message with no text leaves large holes in the
/// conversation, and a bubble that stretches to a fixed width makes "lmk" look like a paragraph.
final class BubbleLayoutTests: XCTestCase {
    private func item(_ kind: MessageKind, text: String?, path: String? = nil) -> ThreadItem {
        ThreadItem(message: ChatMessage(messagePK: 1, kind: kind, text: text, isFromMe: false,
                                        senderJID: "a@lid", date: Date(), durationSeconds: 3,
                                        relativeMediaPath: path),
                   senderName: "A", verdict: nil)
    }

    func testAMessageWithNothingToShowIsNotRendered() {
        XCTAssertFalse(item(.text, text: nil).hasSomethingToShow)
        XCTAssertFalse(item(.text, text: "").hasSomethingToShow)
        XCTAssertFalse(item(.systemEvent, text: nil).hasSomethingToShow)
    }

    func testARealMessageIsRendered() {
        XCTAssertTrue(item(.text, text: "hello").hasSomethingToShow)
        XCTAssertTrue(item(.voiceNote, text: nil, path: "Media/x.opus").hasSomethingToShow)
        XCTAssertTrue(item(.image, text: nil).hasSomethingToShow, "a photo is worth a row even unopened")
        XCTAssertTrue(item(.deleted, text: nil).hasSomethingToShow, "a deletion is information")
    }

    /// A voice note needs room for the waveform whatever it says; text should not.
    func testBubbleWidthFollowsTheContent() {
        XCTAssertEqual(item(.voiceNote, text: nil, path: "p").bubbleWidth, .fixed)
        XCTAssertEqual(item(.text, text: "lmk").bubbleWidth, .hugging)
        XCTAssertEqual(item(.image, text: nil).bubbleWidth, .hugging)
    }

    func testAVerdictForcesTheWiderBubble() {
        let verdict = Verdict(kind: .verified, colour: .green, comparedJID: "a@lid", score: 0.7,
                              best: nil, reason: nil, explanation: "This is A.")
        let judged = ThreadItem(message: item(.voiceNote, text: nil, path: "p").message,
                                senderName: "A", verdict: VerdictRecord(
                                    note: VoiceNoteRecord(messagePK: 1, chatJID: "a@lid",
                                                          senderJID: "a@lid", isFromMe: false,
                                                          date: Date(), durationSeconds: 3,
                                                          relativeMediaPath: "p", chatIsGroup: false),
                                    verdict: verdict, speechSeconds: 3, computedAt: Date(),
                                    modelVersion: "m"))
        XCTAssertEqual(judged.bubbleWidth, .fixed)
    }
}
