import XCTest
@testable import AntiFishCore

/// Every note that can be listened to gets an answer. "Inconclusive" was removed: on real data
/// 54% of genuine notes fell in the old middle band, which told the reader nothing. The only
/// non-answers left are the honest ones — no audio, or too little speech to judge.
final class VerifierTests: XCTestCase {
    private let t = Thresholds(decision: 0.36)
    private let names = ["a@lid": "Abdul", "k@lid": "Karim", "x@lid": "WA ····0001"]

    private func input(_ senderClass: SenderClass, sender: String = "a@lid", claim: String? = nil,
                       speech: Double = 5, scores: [String: Float]) -> VerificationInput {
        VerificationInput(senderJID: sender, senderClass: senderClass, claimedJID: claim,
                          speechSeconds: speech,
                          comparisons: scores.map { Comparison(jid: $0.key, score: $0.value) },
                          names: names)
    }

    // MARK: There is no middle

    func testEveryScoreAboveTheLineVerifies() {
        for score: Float in [0.36, 0.4, 0.5, 0.9] {
            let v = Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": score]), thresholds: t)
            XCTAssertEqual(v.kind, .verified, "score \(score)")
            XCTAssertEqual(v.colour, .green)
        }
    }

    func testEveryScoreBelowTheLineIsFlagged() {
        for score: Float in [0.35, 0.2, 0.0, -0.5] {
            let v = Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": score]), thresholds: t)
            XCTAssertEqual(v.kind, .takeoverSuspected, "score \(score)")
            XCTAssertEqual(v.colour, .red)
        }
    }

    func testNoVerdictIsEverUnclear() {
        let cases: [VerificationInput] = [
            input(.knownEnrolled, scores: ["a@lid": 0.36]),
            input(.knownEnrolled, scores: ["a@lid": 0.30]),
            input(.unknown, sender: "x@lid", claim: "a@lid", scores: ["a@lid": 0.3]),
            input(.unknown, sender: "x@lid", scores: ["a@lid": 0.3, "k@lid": 0.2]),
        ]
        for c in cases {
            XCTAssertNotEqual(Verifier.verdict(c, thresholds: t).kind, .unclear)
        }
    }

    // MARK: A number you have saved

    func testKnownSenderWhoseVoiceMatchesIsVerified() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.6, "k@lid": 0.2]), thresholds: t)
        XCTAssertEqual(v.comparedJID, "a@lid")
        XCTAssertEqual(v.score, 0.6)
        XCTAssertTrue(v.explanation.contains("Abdul"))
    }

    func testKnownSenderWhoseVoiceDoesNotMatchSuggestsTakeover() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.1, "k@lid": 0.7]), thresholds: t)
        XCTAssertEqual(v.kind, .takeoverSuspected)
        XCTAssertTrue(v.isRed)
        XCTAssertTrue(v.explanation.contains("does not sound like"))
        XCTAssertTrue(v.explanation.contains("Karim"), "name the closest known voice")
    }

    func testSavedContactWithoutAFingerprintCannotBeJudged() {
        let v = Verifier.verdict(input(.knownUnenrolled, scores: ["k@lid": 0.9]), thresholds: t)
        XCTAssertEqual(v.kind, .unverifiable)
        XCTAssertEqual(v.reason, "notEnrolled")
    }

    // MARK: A number you have not saved

    func testUnknownNumberClaimingSomeoneItIsNotIsImpersonation() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", claim: "a@lid",
                                       scores: ["a@lid": 0.1, "k@lid": 0.8]), thresholds: t)
        XCTAssertEqual(v.kind, .impersonationSuspected)
        XCTAssertEqual(v.colour, .red)
        XCTAssertEqual(v.comparedJID, "a@lid")
        XCTAssertTrue(v.explanation.contains("Abdul"))
    }

    func testUnknownNumberWhoseVoiceIsSomeoneYouKnowIsAmber() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", scores: ["a@lid": 0.2, "k@lid": 0.7]), thresholds: t)
        XCTAssertEqual(v.kind, .matchesUnsavedNumber)
        XCTAssertEqual(v.colour, .amber, "a voice match on an unsaved number is never green")
        XCTAssertEqual(v.comparedJID, "k@lid")
    }

    func testUnknownNumberThatMatchesItsOwnClaimIsCleared() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", claim: "a@lid",
                                       scores: ["a@lid": 0.7]), thresholds: t)
        XCTAssertEqual(v.kind, .matchesUnsavedNumber)
        XCTAssertEqual(v.comparedJID, "a@lid")
    }

    func testUnknownVoiceWithNoClaimIsJustUnknown() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", scores: ["a@lid": 0.2, "k@lid": 0.1]), thresholds: t)
        XCTAssertEqual(v.kind, .unknownVoice)
        XCTAssertEqual(v.colour, .grey)
    }

    // MARK: The only honest non-answers

    func testTooLittleSpeechIsSaidPlainly() {
        let v = Verifier.verdict(input(.knownEnrolled, speech: 1.0, scores: ["a@lid": 0.9]), thresholds: t)
        XCTAssertEqual(v.kind, .unverifiable)
        XCTAssertEqual(v.reason, "tooShort")
        XCTAssertTrue(v.explanation.contains("Too short"))
    }

    func testNoComparisonsMeansTheModelFailed() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: [:]), thresholds: t)
        XCTAssertEqual(v.kind, .unverifiable)
        XCTAssertEqual(v.reason, "modelFailed")
    }

    func testCalibratedThresholdMoves() {
        let strict = Thresholds(decision: 0.7, calibrated: true)
        XCTAssertEqual(Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.6]), thresholds: strict).kind,
                       .takeoverSuspected)
        XCTAssertEqual(Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.75]), thresholds: strict).kind,
                       .verified)
    }
}
