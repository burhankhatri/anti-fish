import XCTest
@testable import AntiFishCore

/// The demo moment: an unknown number sends a voice note, the user says "this person claims to be
/// Abdul", and the app answers. The claim comes from the user, not from a profile name an
/// impersonator controls, so it is worth treating as a separate entry point.
final class ClaimCheckTests: XCTestCase {
    private let t = Thresholds(decision: 0.36)
    private let names = ["abdul@lid": "Abdul Rehman", "karim@lid": "Karim"]

    private func input(claim: String?, scores: [String: Float], speech: Double = 5) -> VerificationInput {
        VerificationInput(senderJID: "unknown@lid", senderClass: .unknown, claimedJID: claim,
                          speechSeconds: speech,
                          comparisons: scores.map { Comparison(jid: $0.key, score: $0.value) },
                          names: names)
    }

    func testAClaimThatDoesNotHoldIsCalledOut() {
        let v = Verifier.verdict(input(claim: "abdul@lid", scores: ["abdul@lid": 0.05, "karim@lid": 0.1]),
                                 thresholds: t)
        XCTAssertEqual(v.kind, .impersonationSuspected)
        XCTAssertEqual(v.colour, .red)
        XCTAssertTrue(v.explanation.contains("Abdul Rehman"))
    }

    func testAClaimThatHoldsIsCleared() {
        let v = Verifier.verdict(input(claim: "abdul@lid", scores: ["abdul@lid": 0.71]), thresholds: t)
        XCTAssertEqual(v.kind, .matchesUnsavedNumber)
        XCTAssertEqual(v.comparedJID, "abdul@lid")
        XCTAssertTrue(v.explanation.contains("Abdul Rehman"))
    }

    /// Claiming to be one person while sounding like another is the most useful thing the app can
    /// say, so the verdict has to name both.
    func testAClaimThatMatchesSomeoneElseNamesBoth() {
        let v = Verifier.verdict(input(claim: "abdul@lid", scores: ["abdul@lid": 0.4, "karim@lid": 0.82]),
                                 thresholds: t)
        XCTAssertEqual(v.kind, .matchesUnsavedNumber)
        XCTAssertEqual(v.comparedJID, "karim@lid")
        XCTAssertTrue(v.explanation.contains("Karim"))
        XCTAssertTrue(v.explanation.contains("Abdul Rehman"))
    }

    func testCheckingAClaimAgainstSomeoneWithNoFingerprintSaysSo() {
        let v = Verifier.verdict(input(claim: "ghost@lid", scores: ["abdul@lid": 0.1]), thresholds: t)
        XCTAssertEqual(v.kind, .unknownVoice, "a claim we cannot test is not an accusation")
    }

    func testAShortClipStillCannotAccuse() {
        let v = Verifier.verdict(input(claim: "abdul@lid", scores: ["abdul@lid": 0.05], speech: 1.0),
                                 thresholds: t)
        XCTAssertEqual(v.kind, .unverifiable)
        XCTAssertEqual(v.reason, "tooShort")
    }

    /// Who the user can pick from: everyone with a fingerprint, named, most recent first.
    func testClaimCandidatesAreNamedAndOrdered() {
        let old = Fingerprint(jid: "karim@lid", centroid: [1, 0], noteCount: 3, speechSeconds: 40,
                              lastNoteDate: Date(timeIntervalSinceReferenceDate: 1), modelVersion: "m")
        let recent = Fingerprint(jid: "abdul@lid", centroid: [0, 1], noteCount: 5, speechSeconds: 60,
                                 lastNoteDate: Date(timeIntervalSinceReferenceDate: 2), modelVersion: "m")
        let candidates = ClaimCandidate.list(from: [old, recent], names: names)
        XCTAssertEqual(candidates.map(\.jid), ["abdul@lid", "karim@lid"])
        XCTAssertEqual(candidates.first?.name, "Abdul Rehman")
        XCTAssertEqual(candidates.first?.noteCount, 5)
    }

    func testCandidatesWithoutANameStillAppear() {
        let fp = Fingerprint(jid: "555111222@lid", centroid: [1, 0], noteCount: 3, speechSeconds: 40,
                             lastNoteDate: Date(), modelVersion: "m")
        let candidate = ClaimCandidate.list(from: [fp], names: [:]).first
        XCTAssertEqual(candidate?.name, "WA ····1222")
    }
}
