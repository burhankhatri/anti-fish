import XCTest
@testable import AntiFishCore

/// When the user names someone, the answer has to be about that person.
///
/// Seen on a real chat: the user asked "is this Momina?" and the app answered "This really is
/// Shifa", because a passing claim fell through to the best match instead of answering the
/// question that was asked. Another voice really was Momina and came back as "iqra".
final class ClaimAnswerTests: XCTestCase {
    private let t = Thresholds(decision: 0.36)
    private let names = ["momina@lid": "Momina", "shifa@lid": "Shifa", "iqra@lid": "iqra"]

    private func input(claim: String?, scores: [String: Float]) -> VerificationInput {
        VerificationInput(senderJID: "x@lid", senderClass: .unknown, claimedJID: claim,
                          speechSeconds: 8,
                          comparisons: scores.map { Comparison(jid: $0.key, score: $0.value) },
                          names: names)
    }

    /// The question was about Momina, so the answer names Momina, even though Shifa scores higher.
    func testAPassingClaimIsAnsweredAboutTheClaimedPerson() {
        let v = Verifier.verdict(input(claim: "momina@lid",
                                       scores: ["momina@lid": 0.44, "shifa@lid": 0.61]),
                                 thresholds: t)
        XCTAssertEqual(v.comparedJID, "momina@lid")
        XCTAssertTrue(v.explanation.contains("Momina"))
        XCTAssertFalse(v.explanation.hasPrefix("Sounds like Shifa"),
                       "the answer must not be about someone the user did not ask about")
    }

    func testAFailingClaimIsStillAnAccusationAboutTheClaimedPerson() {
        let v = Verifier.verdict(input(claim: "momina@lid",
                                       scores: ["momina@lid": 0.10, "shifa@lid": 0.61]),
                                 thresholds: t)
        XCTAssertEqual(v.kind, .impersonationSuspected)
        XCTAssertEqual(v.comparedJID, "momina@lid")
        XCTAssertTrue(v.explanation.contains("Momina"))
    }

    /// A closer match is worth mentioning, but only after the question has been answered.
    func testACloserMatchIsMentionedSecond() {
        let v = Verifier.verdict(input(claim: "momina@lid",
                                       scores: ["momina@lid": 0.10, "shifa@lid": 0.71]),
                                 thresholds: t)
        let momina = v.explanation.range(of: "Momina")
        let shifa = v.explanation.range(of: "Shifa")
        XCTAssertNotNil(momina)
        XCTAssertNotNil(shifa)
        XCTAssertTrue(momina!.lowerBound < shifa!.lowerBound,
                      "the person asked about comes first: \(v.explanation)")
    }

    /// Naming someone with no baseline cannot be answered, and saying nothing is better than
    /// answering about somebody else.
    func testNamingSomeoneWithNoBaselineSaysSo() {
        let v = Verifier.verdict(input(claim: "ghost@lid",
                                       scores: ["shifa@lid": 0.71]), thresholds: t)
        XCTAssertEqual(v.kind, .unverifiable)
        XCTAssertEqual(v.reason, "notEnrolled")
    }

    /// Without a claim the best match is the right thing to report.
    func testWithoutAClaimTheBestMatchIsReported() {
        let v = Verifier.verdict(input(claim: nil, scores: ["shifa@lid": 0.71, "iqra@lid": 0.2]),
                                 thresholds: t)
        XCTAssertEqual(v.kind, .matchesUnsavedNumber)
        XCTAssertEqual(v.comparedJID, "shifa@lid")
    }
}
