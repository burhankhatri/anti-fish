import XCTest
@testable import AntiFishCore

final class AppDatabaseTests: XCTestCase {
    private let when = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func note(_ jid: String, _ pk: Int64, _ vec: [Float] = [0.5, -0.25]) -> EnrolledNote {
        EnrolledNote(jid: jid, messagePK: pk, embedding: vec, speechSeconds: 3, date: when)
    }

    private func voiceNote(_ pk: Int64, sender: String = "a@lid", chat: String = "a@lid",
                           group: Bool = false) -> VoiceNoteRecord {
        VoiceNoteRecord(messagePK: pk, chatJID: chat, senderJID: sender, isFromMe: false, date: when,
                        durationSeconds: 7, relativeMediaPath: "Media/a@lid/1/2/x.opus", chatIsGroup: group)
    }

    // MARK: Enrolment

    func testEnrolmentNotesRoundTripPerContact() throws {
        let db = try AppDatabase(url: nil)
        let notes = [note("a@lid", 1), note("a@lid", 2, [1, 0])]
        try db.replaceEnrollment(jid: "a@lid", notes: notes)
        try db.replaceEnrollment(jid: "b@lid", notes: [note("b@lid", 3)])
        XCTAssertEqual(try db.enrollmentNotes(jid: "a@lid"), notes)
        XCTAssertEqual(try db.allEnrollmentNotes().count, 3)

        try db.replaceEnrollment(jid: "a@lid", notes: [notes[1]])
        XCTAssertEqual(try db.enrollmentNotes(jid: "a@lid").map(\.messagePK), [2])
        XCTAssertEqual(try db.enrollmentNotes(jid: "b@lid").count, 1, "other contacts are untouched")
    }

    func testEmbeddingsSurviveTheRoundTripExactly() throws {
        let db = try AppDatabase(url: nil)
        let vec: [Float] = [0.123_456_7, -0.987_654_3, 0]
        try db.replaceEnrollment(jid: "a@lid", notes: [note("a@lid", 1, vec)])
        XCTAssertEqual(try db.enrollmentNotes(jid: "a@lid").first?.embedding, vec)
    }

    // MARK: Fingerprints and the centre

    func testFingerprintsAreReplacedWholesale() throws {
        let db = try AppDatabase(url: nil)
        let fp = Fingerprint(jid: "a@lid", centroid: [1, 0], noteCount: 3, speechSeconds: 40,
                             lastNoteDate: when, modelVersion: "m1")
        try db.saveFingerprints([fp])
        XCTAssertEqual(try db.fingerprints(), [fp])
        try db.saveFingerprints([])
        XCTAssertEqual(try db.fingerprints(), [])
    }

    func testEmbeddingCentreRoundTrips() throws {
        let db = try AppDatabase(url: nil)
        XCTAssertTrue(try db.embeddingCenter().isIdentity)
        let center = EmbeddingCenter(embeddings: [[1, 0], [0, 1]])
        try db.saveEmbeddingCenter(center)
        XCTAssertEqual(try db.embeddingCenter(), center)
    }

    // MARK: Verdicts

    func testVerdictsComeBackNewestFirst() throws {
        let db = try AppDatabase(url: nil)
        let verdict = Verdict(kind: .verified, colour: .green, comparedJID: "a@lid", score: 0.71,
                              best: Comparison(jid: "a@lid", score: 0.71), reason: nil, explanation: "ok")
        try db.saveVerdict(VerdictRecord(note: voiceNote(10), verdict: verdict, speechSeconds: 5.5,
                                         computedAt: when, modelVersion: "m1"))
        try db.saveVerdict(VerdictRecord(note: voiceNote(11, sender: "k@lid", chat: "g@g.us", group: true),
                                         verdict: .unverifiable(.mediaMissing, explanation: "gone"),
                                         speechSeconds: 0, computedAt: when.addingTimeInterval(60),
                                         modelVersion: "m1"))
        XCTAssertEqual(try db.verdicts(limit: 10).map(\.messagePK), [11, 10])
        XCTAssertEqual(try db.verdicts(limit: 1).map(\.messagePK), [11])
    }

    func testVerdictFieldsRoundTrip() throws {
        let db = try AppDatabase(url: nil)
        let verdict = Verdict(kind: .verified, colour: .green, comparedJID: "a@lid", score: 0.71,
                              best: Comparison(jid: "a@lid", score: 0.71), reason: nil, explanation: "ok")
        try db.saveVerdict(VerdictRecord(note: voiceNote(10), verdict: verdict, speechSeconds: 5.5,
                                         computedAt: when, modelVersion: "m1"))
        let row = try XCTUnwrap(try db.verdict(messagePK: 10))
        XCTAssertEqual(row.kind, "verified")
        XCTAssertEqual(row.colour, "green")
        XCTAssertEqual(row.score ?? 0, 0.71, accuracy: 1e-6)
        XCTAssertEqual(row.bestJID, "a@lid")
        XCTAssertEqual(row.chatJID, "a@lid")
        XCTAssertEqual(row.durationSeconds, 7)
        XCTAssertEqual(row.relativeMediaPath, "Media/a@lid/1/2/x.opus")
        XCTAssertEqual(row.date, when)
        XCTAssertFalse(row.isRed)
        XCTAssertNil(try db.verdict(messagePK: 12))
    }

    func testResavingAVerdictReplacesIt() throws {
        let db = try AppDatabase(url: nil)
        let grey = Verdict(kind: .unknownVoice, colour: .grey, comparedJID: nil, score: nil,
                           best: nil, reason: nil, explanation: "unknown")
        try db.saveVerdict(VerdictRecord(note: voiceNote(10), verdict: grey, speechSeconds: 4,
                                         computedAt: when, modelVersion: "m1"))
        let red = Verdict(kind: .impersonationSuspected, colour: .red, comparedJID: "a@lid", score: 0.1,
                          best: nil, reason: nil, explanation: "impostor")
        try db.saveVerdict(VerdictRecord(note: voiceNote(10), verdict: red, speechSeconds: 4,
                                         computedAt: when, modelVersion: "m1"))
        XCTAssertEqual(try db.verdicts(limit: 10).count, 1)
        XCTAssertTrue(try XCTUnwrap(db.verdict(messagePK: 10)).isRed)
    }

    // MARK: Contacts

    func testContactsUpsertAndSort() throws {
        let db = try AppDatabase(url: nil)
        try db.saveContacts([ContactRecord(jid: "a@lid", displayName: "Abdul", isSaved: true,
                                           pinned: false, blacklisted: false, avatarPath: nil)])
        try db.saveContacts([ContactRecord(jid: "a@lid", displayName: "Abdul T.", isSaved: true,
                                           pinned: true, blacklisted: false, avatarPath: "p")])
        let contacts = try db.contacts()
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].displayName, "Abdul T.")
        XCTAssertTrue(contacts[0].pinned)
        XCTAssertEqual(contacts[0].avatarPath, "p")
    }

    // MARK: Settings

    func testSettingsThresholdsAndCursor() throws {
        let db = try AppDatabase(url: nil)
        XCTAssertEqual(try db.thresholds(), Thresholds())
        XCTAssertEqual(try db.lastSeenMessagePK(), 0)
        XCTAssertNil(try db.calibration())

        let result = CalibrationResult(thresholds: Thresholds(reject: 0.3, match: 0.6, calibrated: true),
                                       contactCount: 7, genuineCount: 20, impostorCount: 120,
                                       genuineMedian: 0.8, impostorMedian: 0.1, calibratedAt: when)
        try db.saveCalibration(result)
        XCTAssertEqual(try db.thresholds(), result.thresholds)
        XCTAssertEqual(try db.calibration(), result)

        try db.setLastSeenMessagePK(4242)
        XCTAssertEqual(try db.lastSeenMessagePK(), 4242)
    }

    func testFileBackedDatabaseCreatesItsDirectoryAndPersists() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("nested/dir/antifish.sqlite")
        let db = try AppDatabase(url: url)
        try db.setLastSeenMessagePK(9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try AppDatabase(url: url).lastSeenMessagePK(), 9, "reopening keeps the data")
    }
}
