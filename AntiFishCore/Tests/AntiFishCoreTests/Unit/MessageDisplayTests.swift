import XCTest
@testable import AntiFishCore

/// A thread that draws a bubble for every row, including the ones with nothing in them, ends up
/// full of holes. And a bubble sized to a fixed width makes "lmk" look like a paragraph.
final class MessageDisplayTests: XCTestCase {
    private func message(_ kind: MessageKind, text: String? = nil, path: String? = nil) -> ChatMessage {
        ChatMessage(messagePK: 1, kind: kind, text: text, isFromMe: false, senderJID: "a@lid",
                    date: Date(), durationSeconds: 3, relativeMediaPath: path)
    }

    func testAMessageWithNothingToShowIsSkipped() {
        XCTAssertFalse(message(.text).hasSomethingToShow)
        XCTAssertFalse(message(.text, text: "").hasSomethingToShow)
        XCTAssertFalse(message(.text, text: "   \n ").hasSomethingToShow)
        XCTAssertFalse(message(.systemEvent).hasSomethingToShow)
        XCTAssertFalse(message(.other).hasSomethingToShow)
    }

    func testARealMessageIsShown() {
        XCTAssertTrue(message(.text, text: "hello").hasSomethingToShow)
        XCTAssertTrue(message(.link, text: "https://x.com").hasSomethingToShow)
        XCTAssertTrue(message(.voiceNote, path: "Media/x.opus").hasSomethingToShow)
        XCTAssertTrue(message(.voiceNote).hasSomethingToShow, "a note with no audio still happened")
        XCTAssertTrue(message(.image).hasSomethingToShow)
        XCTAssertTrue(message(.deleted).hasSomethingToShow, "a deletion is information")
    }

    /// A waveform needs consistent room. Text does not.
    func testOnlyVoiceNotesNeedAFixedWidth() {
        XCTAssertTrue(message(.voiceNote, path: "p").needsFixedWidth)
        XCTAssertFalse(message(.text, text: "lmk").needsFixedWidth)
        XCTAssertFalse(message(.image).needsFixedWidth)
        XCTAssertFalse(message(.deleted).needsFixedWidth)
    }
}
