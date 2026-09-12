import XCTest
@testable import AntiFishCore

/// Catches the scams that have no pixels to analyse: a doctored payment screenshot, a message
/// demanding an OTP, a "this is my new number" from a stranger. Runs on this Mac with no service
/// and no quota, which also means it keeps working when the image check has run out.
final class ScamTextTests: XCTestCase {

    // MARK: Money

    func testAPaymentClaimFromAStrangerIsFlagged() {
        let signals = ScamText.signals(in: "I have transferred Rs. 25,000 to your account, please confirm")
        XCTAssertTrue(signals.contains(.paymentClaim))
    }

    func testPaymentClaimsInRomanUrdu() {
        XCTAssertTrue(ScamText.signals(in: "paise bhej diye hain, check karo").contains(.paymentClaim))
        XCTAssertTrue(ScamText.signals(in: "PKR 50000 transfer ho gaya").contains(.paymentClaim))
    }

    func testAnOrdinarySentenceAboutMoneyIsNotAScam() {
        XCTAssertFalse(ScamText.signals(in: "lunch was 500 rupees, split it later").contains(.paymentClaim))
    }

    // MARK: Credentials

    func testAskingForAOneTimeCodeIsFlagged() {
        for text in ["send me the OTP", "share the code you received", "what is your PIN",
                     "forward the verification code"] {
            XCTAssertTrue(ScamText.signals(in: text).contains(.credentialRequest), text)
        }
    }

    func testAskingForAnIdentityDocumentIsFlagged() {
        XCTAssertTrue(ScamText.signals(in: "send your CNIC picture for verification")
            .contains(.credentialRequest))
    }

    // MARK: Pressure

    func testUrgencyIsFlagged() {
        for text in ["act now, offer expires today", "urgent: reply immediately",
                     "last chance, only 2 hours left"] {
            XCTAssertTrue(ScamText.signals(in: text).contains(.urgency), text)
        }
    }

    func testPrizeBaitIsFlagged() {
        XCTAssertTrue(ScamText.signals(in: "Congratulations! You have won a lucky draw prize")
            .contains(.prizeBait))
    }

    func testAdvanceFeeIsFlagged() {
        XCTAssertTrue(ScamText.signals(in: "pay a small processing fee to release your payment")
            .contains(.advanceFee))
    }

    func testNewNumberClaimIsFlagged() {
        XCTAssertTrue(ScamText.signals(in: "hi this is my new number, save it")
            .contains(.newNumberClaim))
    }

    // MARK: Ordinary conversation must stay quiet

    func testEverydayMessagesAreClean() {
        for text in ["are you coming to dinner", "lmk when you reach",
                     "here are the photos from yesterday", "meeting moved to 3pm",
                     "happy birthday!", "send me the file when you can"] {
            XCTAssertTrue(ScamText.signals(in: text).isEmpty, "false positive on: \(text)")
        }
    }

    func testEmptyTextHasNoSignals() {
        XCTAssertTrue(ScamText.signals(in: "").isEmpty)
        XCTAssertTrue(ScamText.signals(in: "   ").isEmpty)
    }

    // MARK: Risk depends on who is speaking

    /// The same words mean different things from your mother and from a number you have never seen.
    func testRiskRisesWhenTheSenderIsUnknown() {
        let text = "I have transferred Rs 25,000, send the goods now"
        let known = ScamText.assess(text, senderIsKnown: true)
        let stranger = ScamText.assess(text, senderIsKnown: false)
        XCTAssertGreaterThan(stranger.score, known.score)
        XCTAssertTrue(stranger.isWorrying)
    }

    func testTwoSignalsTogetherAreWorseThanOne() {
        let one = ScamText.assess("please send the OTP", senderIsKnown: false)
        let two = ScamText.assess("urgent! send the OTP immediately or your account is blocked",
                                  senderIsKnown: false)
        XCTAssertGreaterThan(two.score, one.score)
    }

    func testACleanMessageFromAnyoneIsNotWorrying() {
        XCTAssertFalse(ScamText.assess("see you at 5", senderIsKnown: false).isWorrying)
    }

    /// The summary is what a person reads, so it has to be a sentence.
    func testTheSummaryReadsAsPlainWords() {
        let assessment = ScamText.assess("send me the OTP urgently", senderIsKnown: false)
        XCTAssertFalse(assessment.summary.isEmpty)
        XCTAssertFalse(assessment.summary.contains("_"))
        XCTAssertTrue(assessment.summary.lowercased().contains("code"))
    }

    func testACleanMessageHasNoSummary() {
        XCTAssertTrue(ScamText.assess("ok", senderIsKnown: true).summary.isEmpty)
    }
}
