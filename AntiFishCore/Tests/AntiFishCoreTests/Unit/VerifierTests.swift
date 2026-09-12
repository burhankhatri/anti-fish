import XCTest
@testable import AntiFishCore

final class VerifierTests: XCTestCase {
    private let t = Thresholds()   // reject 0.25, match 0.45
    private let names = ["a@lid": "Abdul", "k@lid": "Karim", "x@lid": "WA ····0001"]

    private func input(_ senderClass: SenderClass, sender: String = "a@lid", claim: String? = nil,
                       speech: Double = 5, scores: [String: Float]) -> VerificationInput {
        VerificationInput(senderJID: sender, senderClass: senderClass, claimedJID: claim,
                          speechSeconds: speech,
                          comparisons: scores.map { Comparison(jid: $0.key, score: $0.value) },
                          names: names)
    }

    // MARK: A number you have saved

    func testKnownSenderWhoseVoiceMatchesIsVerified() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.6, "k@lid": 0.2]), thresholds: t)
        XCTAssertEqual(v.kind, .verified)
        XCTAssertEqual(v.colour, .green)
        XCTAssertEqual(v.comparedJID, "a@lid")
        XCTAssertEqual(v.score, 0.6)
        XCTAssertTrue(v.explanation.contains("Abdul"))
    }

    func testKnownSenderWhoseVoiceDoesNotMatchSuggestsTakeover() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.1, "k@lid": 0.7]), thresholds: t)
        XCTAssertEqual(v.kind, .takeoverSuspected)
        XCTAssertEqual(v.colour, .red)
        XCTAssertTrue(v.isRed)
        XCTAssertTrue(v.explanation.contains("does not match"))
        XCTAssertTrue(v.explanation.contains("Karim"), "name the closest known voice")
    }

    func testKnownSenderInTheMiddleIsUnclear() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.35]), thresholds: t)
        XCTAssertEqual(v.kind, .unclear)
        XCTAssertEqual(v.reason, "borderline")
    }

    func testSavedContactWithoutAFingerprintCannotBeJudged() {
        let v = Verifier.verdict(input(.knownUnenrolled, scores: ["k@lid": 0.9]), thresholds: t)
        XCTAssertEqual(v.kind, .unverifiable)
        XCTAssertEqual(v.reason, "notEnrolled")
        XCTAssertEqual(v.colour, .grey)
    }

    func testKnownSenderMissingTheirOwnComparisonIsUnverifiable() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: ["k@lid": 0.9]), thresholds: t)
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
        XCTAssertEqual(v.best?.jid, "k@lid")
        XCTAssertTrue(v.explanation.contains("Abdul"))
    }

    func testUnknownNumberWhoseVoiceIsSomeoneYouKnowIsAmber() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", scores: ["a@lid": 0.2, "k@lid": 0.7]), thresholds: t)
        XCTAssertEqual(v.kind, .matchesUnsavedNumber)
        XCTAssertEqual(v.colour, .amber, "a voice match on an unsaved number is never green")
        XCTAssertEqual(v.comparedJID, "k@lid")
        XCTAssertTrue(v.explanation.contains("Karim"))
    }

    func testUnknownNumberWithAClaimAndAnInconclusiveScoreIsUnclear() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", claim: "a@lid",
                                       scores: ["a@lid": 0.3, "k@lid": 0.3]), thresholds: t)
        XCTAssertEqual(v.kind, .unclear)
        XCTAssertEqual(v.reason, "borderline")
        XCTAssertEqual(v.comparedJID, "a@lid")
    }

    func testUnknownVoiceWithNoClaimIsJustUnknown() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", scores: ["a@lid": 0.2, "k@lid": 0.1]), thresholds: t)
        XCTAssertEqual(v.kind, .unknownVoice)
        XCTAssertEqual(v.colour, .grey)
        XCTAssertEqual(v.best?.jid, "a@lid")
    }

    // MARK: How much speech is enough

    func testTooLittleSpeechBeatsEveryOtherOutcome() {
        let v = Verifier.verdict(input(.knownEnrolled, speech: 1.0, scores: ["a@lid": 0.9]), thresholds: t)
        XCTAssertEqual(v.kind, .unclear)
        XCTAssertEqual(v.reason, "tooShort")
    }

    func testVerifiedNeedsTwoSecondsOfSpeech() {
        let v = Verifier.verdict(input(.knownEnrolled, speech: 1.8, scores: ["a@lid": 0.6]), thresholds: t)
        XCTAssertEqual(v.kind, .unclear)
        XCTAssertEqual(v.reason, "shortClip")
    }

    func testAnAccusationNeedsThreeSecondsOfSpeech() {
        let takeover = Verifier.verdict(input(.knownEnrolled, speech: 2.5, scores: ["a@lid": 0.1]), thresholds: t)
        XCTAssertEqual(takeover.kind, .unclear)
        XCTAssertEqual(takeover.reason, "shortClip")
        XCTAssertEqual(takeover.colour, .amber)

        let impersonation = Verifier.verdict(input(.unknown, sender: "x@lid", claim: "a@lid", speech: 2,
                                                   scores: ["a@lid": 0.1]), thresholds: t)
        XCTAssertEqual(impersonation.kind, .unclear)
        XCTAssertEqual(impersonation.reason, "shortClip")
    }

    func testNoComparisonsMeansTheModelFailed() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: [:]), thresholds: t)
        XCTAssertEqual(v.kind, .unverifiable)
        XCTAssertEqual(v.reason, "modelFailed")
    }

    func testCalibratedThresholdsAreRespected() {
        let strict = Thresholds(reject: 0.5, match: 0.8, calibrated: true)
        XCTAssertEqual(Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.6]), thresholds: strict).kind, .unclear)
        XCTAssertEqual(Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.85]), thresholds: strict).kind, .verified)
        XCTAssertEqual(Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.4]), thresholds: strict).kind, .takeoverSuspected)
    }
}
