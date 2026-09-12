import XCTest
@testable import AntiFishCore

/// Two faults seen together on a real chat: every note said "not enough of Momina's voice yet"
/// long after she had been enrolled, because the verdicts were stored before the baseline existed
/// and nothing re-ran them. And asking "is this Momina?" about Momina's own saved number answered
/// "from a number you have not saved", because naming someone forced the unknown-caller path.
final class StaleVerdictTests: XCTestCase {

    // MARK: Stale verdicts

    func testVerdictsThatCouldNotBeJudgedAreCleared() throws {
        let db = try AppDatabase(url: nil)
        let note = VoiceNoteRecord(messagePK: 7, chatJID: "m@lid", senderJID: "m@lid",
                                   isFromMe: false, date: Date(), durationSeconds: 6,
                                   relativeMediaPath: "Media/m/7.opus", chatIsGroup: false)
        try db.saveVerdict(VerdictRecord(note: note,
                                         verdict: .unverifiable(.notEnrolled, explanation: "no baseline"),
                                         speechSeconds: 5, computedAt: Date(), modelVersion: "m"))
        XCTAssertNotNil(try db.verdict(messagePK: 7))

        let cleared = try db.clearUnverifiableVerdicts(for: ["m@lid"], reason: .notEnrolled)
        XCTAssertEqual(cleared, 1)
        XCTAssertNil(try db.verdict(messagePK: 7), "it must be judged again now there is a baseline")
    }

    func testARealVerdictIsNeverCleared() throws {
        let db = try AppDatabase(url: nil)
        let note = VoiceNoteRecord(messagePK: 8, chatJID: "m@lid", senderJID: "m@lid",
                                   isFromMe: false, date: Date(), durationSeconds: 6,
                                   relativeMediaPath: "Media/m/8.opus", chatIsGroup: false)
        try db.saveVerdict(VerdictRecord(note: note,
                                         verdict: Verdict(kind: .verified, colour: .green,
                                                          comparedJID: "m@lid", score: 0.8, best: nil,
                                                          reason: nil, explanation: "ok"),
                                         speechSeconds: 5, computedAt: Date(), modelVersion: "m"))
        XCTAssertEqual(try db.clearUnverifiableVerdicts(for: ["m@lid"], reason: .notEnrolled), 0)
        XCTAssertNotNil(try db.verdict(messagePK: 8))
    }

    func testOnlyTheNamedSendersAreTouched() throws {
        let db = try AppDatabase(url: nil)
        for (pk, jid) in [(1 as Int64, "m@lid"), (2, "other@lid")] {
            let note = VoiceNoteRecord(messagePK: pk, chatJID: jid, senderJID: jid, isFromMe: false,
                                       date: Date(), durationSeconds: 6,
                                       relativeMediaPath: "Media/x.opus", chatIsGroup: false)
            try db.saveVerdict(VerdictRecord(note: note,
                                             verdict: .unverifiable(.notEnrolled, explanation: "x"),
                                             speechSeconds: 5, computedAt: Date(), modelVersion: "m"))
        }
        XCTAssertEqual(try db.clearUnverifiableVerdicts(for: ["m@lid"], reason: .notEnrolled), 1)
        XCTAssertNil(try db.verdict(messagePK: 1))
        XCTAssertNotNil(try db.verdict(messagePK: 2))
    }

    // MARK: Naming the person who is actually the sender

    /// Asking "is this Momina?" about Momina's own saved number is the ordinary verified case,
    /// not an unknown caller.
    func testNamingTheSenderThemselvesGivesAPlainAnswer() {
        let input = VerificationInput(senderJID: "m@lid", senderClass: .knownEnrolled,
                                      claimedJID: "m@lid", speechSeconds: 6,
                                      comparisons: [Comparison(jid: "m@lid", score: 0.72)],
                                      names: ["m@lid": "Momina"])
        let verdict = Verifier.verdict(input, thresholds: Thresholds(decision: 0.36))
        XCTAssertEqual(verdict.kind, .verified)
        XCTAssertEqual(verdict.colour, .green)
        XCTAssertFalse(verdict.explanation.contains("not saved"),
                       "a saved contact should not be described as unsaved")
        XCTAssertTrue(verdict.explanation.contains("Momina"))
    }

    func testNamingTheSenderWhenTheVoiceDoesNotMatchStillWarns() {
        let input = VerificationInput(senderJID: "m@lid", senderClass: .knownEnrolled,
                                      claimedJID: "m@lid", speechSeconds: 6,
                                      comparisons: [Comparison(jid: "m@lid", score: 0.05)],
                                      names: ["m@lid": "Momina"])
        let verdict = Verifier.verdict(input, thresholds: Thresholds(decision: 0.36))
        XCTAssertEqual(verdict.kind, .takeoverSuspected)
        XCTAssertEqual(verdict.colour, .red)
    }

    /// Naming someone else about an unknown number is still the impersonation question.
    func testNamingSomeoneElseKeepsTheUnknownPath() {
        let input = VerificationInput(senderJID: "x@lid", senderClass: .unknown,
                                      claimedJID: "m@lid", speechSeconds: 6,
                                      comparisons: [Comparison(jid: "m@lid", score: 0.05)],
                                      names: ["m@lid": "Momina", "x@lid": "WA ····1234"])
        XCTAssertEqual(Verifier.verdict(input, thresholds: Thresholds(decision: 0.36)).kind,
                       .impersonationSuspected)
    }
}
