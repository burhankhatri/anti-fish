import XCTest
@testable import AntiFishCore

final class CoordinatorIntegrationTests: XCTestCase {
    private func makeCoordinator() throws -> (Coordinator, AppDatabase, CoordinatorConfig) {
        let config = CoordinatorConfig(locator: ContainerLocator(),
                                       models: ModelPaths(directory: TestEnv.modelsDir))
        let db = try AppDatabase(url: nil)
        let engine = try VoiceEngine(models: config.models, numThreads: 4)
        return (Coordinator(config: config, db: db, engine: engine), db, config)
    }

    /// The whole pipeline against this Mac's real WhatsApp data: enrol everyone with enough voice,
    /// learn thresholds from them, then judge the newest incoming note.
    func testEnrolCalibrateAndVerifyOnRealData() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (coordinator, db, config) = try makeCoordinator()

        let fingerprints = try await coordinator.enrollAll()
        print("COORDINATOR enrolled=\(fingerprints.count)")
        XCTAssertGreaterThanOrEqual(fingerprints.count, 10, "this Mac has at least ten voices with enough audio")
        XCTAssertTrue(fingerprints.allSatisfy { $0.noteCount >= 3 })
        XCTAssertTrue(fingerprints.allSatisfy { $0.speechSeconds >= 30 })
        XCTAssertTrue(fingerprints.allSatisfy { $0.centroid.count == 256 })

        XCTAssertFalse(try db.embeddingCenter().isIdentity, "enrolment must produce a centre")

        let calibration = try XCTUnwrap(try db.calibration())
        print("COORDINATOR calibration contacts=\(calibration.contactCount) genuineMedian=\(calibration.genuineMedian) impostorMedian=\(calibration.impostorMedian) reject=\(calibration.thresholds.reject) match=\(calibration.thresholds.match)")
        XCTAssertGreaterThanOrEqual(calibration.contactCount, Calibrator.minContacts)
        XCTAssertTrue(calibration.thresholds.calibrated)
        XCTAssertLessThan(calibration.thresholds.reject, calibration.thresholds.match)
        XCTAssertGreaterThan(calibration.genuineMedian, calibration.impostorMedian + 0.3,
                             "real contacts must separate clearly once the space is centred")

        let contacts = try db.contacts()
        XCTAssertGreaterThanOrEqual(contacts.count, fingerprints.count)
        XCTAssertTrue(contacts.contains { $0.isSaved }, "some voice-note senders are saved contacts")

        let store = try ChatStore.open(url: config.locator.chatStorageURL)
        let newest = try XCTUnwrap(try VoiceNoteQuery.fetch(store).last { note in
            !note.isFromMe && !note.senderJID.hasPrefix("status@")
                && FileManager.default.fileExists(atPath: config.locator.mediaURL(relativePath: note.relativeMediaPath).path)
        })
        let record = try await coordinator.verify(newest)
        print("COORDINATOR newest verdict=\(record.kind) colour=\(record.colour) score=\(record.score ?? -1)")
        XCTAssertEqual(record.messagePK, newest.messagePK)
        XCTAssertNotEqual(record.reason, UnverifiableReason.mediaMissing.rawValue)
        XCTAssertNotEqual(record.reason, UnverifiableReason.decodeFailed.rawValue)
        XCTAssertEqual(try db.verdict(messagePK: newest.messagePK)?.kind, record.kind)
    }

    /// Most notes from a saved, enrolled contact should come back verified. This is the number
    /// that decides whether the product is usable day to day.
    func testKnownContactsAreMostlyVerified() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (coordinator, db, config) = try makeCoordinator()
        _ = try await coordinator.enrollAll()

        let enrolled = Set(try db.fingerprints().map(\.jid))
        let saved = Set(try db.contacts().filter(\.isSaved).map(\.jid))
        let judgeable = enrolled.intersection(saved)
        try XCTSkipUnless(judgeable.count >= 3, "needs at least three saved, enrolled contacts")

        let store = try ChatStore.open(url: config.locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store).filter {
            judgeable.contains($0.senderJID) && !$0.isFromMe && $0.durationSeconds >= 5
                && FileManager.default.fileExists(atPath: config.locator.mediaURL(relativePath: $0.relativeMediaPath).path)
        }.suffix(20)

        var verified = 0, red = 0
        for note in notes {
            let r = try await coordinator.verify(note)
            if r.kind == VerdictKind.verified.rawValue { verified += 1 }
            if r.isRed { red += 1 }
        }
        print("COORDINATOR known-contact notes=\(notes.count) verified=\(verified) red=\(red)")
        XCTAssertGreaterThan(verified, notes.count / 2, "most notes from a known contact should verify")
        XCTAssertLessThanOrEqual(red, notes.count / 5, "false impersonation alarms must stay rare")
    }

    func testProcessNewVerifiesRecentNotesAndAdvancesTheCursor() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (coordinator, db, config) = try makeCoordinator()
        _ = try await coordinator.enrollAll()

        let store = try ChatStore.open(url: config.locator.chatStorageURL)
        let maxPK = try VoiceNoteQuery.maxMessagePK(store)
        try db.setLastSeenMessagePK(maxPK - 300)

        let verdicts = try await coordinator.processNew()
        print("COORDINATOR processNew produced \(verdicts.count) verdicts")
        XCTAssertGreaterThan(verdicts.count, 0)
        XCTAssertTrue(verdicts.allSatisfy { $0.messagePK > maxPK - 300 })
        XCTAssertGreaterThanOrEqual(try db.lastSeenMessagePK(), maxPK - 300)
        let second = try await coordinator.processNew()
        XCTAssertEqual(second.count, 0, "a second pass has nothing left to do")
    }
}
