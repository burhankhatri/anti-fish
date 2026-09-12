import XCTest
@testable import AntiFishCore

final class EnrollerTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let policy = EnrollmentPolicy()

    private func note(_ jid: String, pk: Int64, secs: Double = 12, daysAgo: Double = 0,
                      vec: [Float] = [1, 0]) -> EnrolledNote {
        EnrolledNote(jid: jid, messagePK: pk, embedding: vec, speechSeconds: secs,
                     date: Date(timeIntervalSinceReferenceDate: 1_000_000 - daysAgo * day))
    }

    func testSenderNeedsEnoughNotesAndEnoughSpeech() {
        let notes = [
            note("a@lid", pk: 1), note("a@lid", pk: 2), note("a@lid", pk: 3),            // 36 s: enrolled
            note("b@lid", pk: 4), note("b@lid", pk: 5),                                   // 2 notes: no
            note("c@lid", pk: 6, secs: 5), note("c@lid", pk: 7, secs: 5), note("c@lid", pk: 8, secs: 5),
        ]
        let fps = Enroller.fingerprints(from: notes, policy: policy, center: .identity, modelVersion: "m1")
        XCTAssertEqual(fps.map(\.jid), ["a@lid"])
        XCTAssertEqual(fps[0].noteCount, 3)
        XCTAssertEqual(fps[0].speechSeconds, 36)
        XCTAssertEqual(fps[0].modelVersion, "m1")
        XCTAssertEqual(Vector.cosine(fps[0].centroid, [1, 0]), 1, accuracy: 1e-6)
    }

    func testOnlyTheNewestNotesFeedTheCentroid() {
        let notes = (0..<40).map { i in note("d@lid", pk: Int64(i), daysAgo: Double(i)) }
        let fp = Enroller.fingerprints(from: notes, policy: policy, center: .identity, modelVersion: "m1")[0]
        XCTAssertEqual(fp.noteCount, policy.maxNotes)
        XCTAssertEqual(fp.lastNoteDate, notes[0].date)
    }

    func testCentroidIsBuiltInTheCentredSpace() {
        let center = EmbeddingCenter(embeddings: [[1, 0], [0, 1]])
        let notes = (1...3).map { note("a@lid", pk: Int64($0), vec: [1, 0]) }
        let fp = Enroller.fingerprints(from: notes, policy: policy, center: center, modelVersion: "m1")[0]
        XCTAssertEqual(Vector.cosine(fp.centroid, center.project([1, 0])), 1, accuracy: 1e-5)
        XCTAssertLessThan(Vector.cosine(fp.centroid, [1, 0]), 0.99)
    }

    func testNotesWithoutAnEmbeddingAreIgnoredAndOrderIsByRecency() {
        let notes = [
            note("old@lid", pk: 1, daysAgo: 10), note("old@lid", pk: 2, daysAgo: 11), note("old@lid", pk: 3, daysAgo: 12),
            note("new@lid", pk: 4), note("new@lid", pk: 5), note("new@lid", pk: 6),
            note("empty@lid", pk: 7, vec: []), note("empty@lid", pk: 8, vec: []), note("empty@lid", pk: 9, vec: []),
        ]
        XCTAssertEqual(Enroller.fingerprints(from: notes, policy: policy, center: .identity, modelVersion: "m1").map(\.jid),
                       ["new@lid", "old@lid"])
    }

    func testProtectedIsTheMostRecentTenWithPinsFirst() {
        let notes = (0..<12).flatMap { s in (0..<3).map { n in note("s\(s)@lid", pk: Int64(s * 10 + n), daysAgo: Double(s)) } }
        let fps = Enroller.fingerprints(from: notes, policy: policy, center: .identity, modelVersion: "m1")
        let plain = Enroller.protectedJIDs(fps, pinned: [], policy: policy)
        XCTAssertEqual(plain.count, policy.protectedCount)
        XCTAssertEqual(plain.first, "s0@lid")
        XCTAssertFalse(plain.contains("s11@lid"))

        let pinned = Enroller.protectedJIDs(fps, pinned: ["s11@lid", "ghost@lid"], policy: policy)
        XCTAssertEqual(pinned.first, "s11@lid")
        XCTAssertEqual(pinned.count, policy.protectedCount)
        XCTAssertFalse(pinned.contains("ghost@lid"), "a pin for someone unenrolled must not take a slot")
    }

    /// The rolling update is what stops an impostor's note from poisoning a fingerprint.
    func testRollingAppendOnlyAcceptsVerifiedNotesFromTheSameSender() {
        let t = Thresholds()
        let existing = [note("a@lid", pk: 1), note("a@lid", pk: 2)]
        let good = note("a@lid", pk: 3, secs: 4)
        XCTAssertEqual(Enroller.rollingAppend(existing: existing, candidate: good, score: 0.6,
                                              thresholds: t, policy: policy)?.count, 3)
        XCTAssertNil(Enroller.rollingAppend(existing: existing, candidate: good, score: 0.4,
                                            thresholds: t, policy: policy), "below the match threshold")
        XCTAssertNil(Enroller.rollingAppend(existing: existing, candidate: note("a@lid", pk: 3, secs: 1.5),
                                            score: 0.9, thresholds: t, policy: policy), "too little speech")
        XCTAssertNil(Enroller.rollingAppend(existing: existing, candidate: note("b@lid", pk: 3, secs: 4),
                                            score: 0.9, thresholds: t, policy: policy), "different sender")
        XCTAssertNil(Enroller.rollingAppend(existing: existing, candidate: note("a@lid", pk: 2, secs: 4),
                                            score: 0.9, thresholds: t, policy: policy), "already enrolled")
        XCTAssertNil(Enroller.rollingAppend(existing: existing, candidate: note("a@lid", pk: 3, secs: 4, vec: []),
                                            score: 0.9, thresholds: t, policy: policy), "no embedding")
    }

    func testRollingAppendKeepsTheNewestNotes() {
        let existing = (1...30).map { i in note("a@lid", pk: Int64(i), daysAgo: Double(i)) }
        let newest = note("a@lid", pk: 99, secs: 4)
        let merged = try! XCTUnwrap(Enroller.rollingAppend(existing: existing, candidate: newest, score: 0.9,
                                                           thresholds: Thresholds(), policy: policy))
        XCTAssertEqual(merged.count, policy.maxNotes)
        XCTAssertEqual(merged.first?.messagePK, 99)
        XCTAssertFalse(merged.contains { $0.messagePK == 30 }, "the oldest note drops off")
    }

    func testDefaultThresholdsAreTheMeasuredOnes() {
        let t = Thresholds()
        XCTAssertEqual(t.reject, 0.25)
        XCTAssertEqual(t.match, 0.45)
        XCTAssertFalse(t.calibrated)
    }
}
