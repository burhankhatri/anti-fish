import XCTest
@testable import AntiFishCore

final class CoordinatorActionsIntegrationTests: XCTestCase {
    private func enrolled() async throws -> (Coordinator, AppDatabase, CoordinatorConfig, [Fingerprint]) {
        let config = CoordinatorConfig(locator: ContainerLocator(),
                                       models: ModelPaths(directory: TestEnv.modelsDir))
        let db = try AppDatabase(url: nil)
        let coordinator = Coordinator(config: config, db: db,
                                      engine: try VoiceEngine(models: config.models, numThreads: 4))
        let fingerprints = try await coordinator.enrollAll()
        return (coordinator, db, config, fingerprints)
    }

    /// The user overruling the app has to stick: the note joins that contact's enrolment and the
    /// verdict flips to verified.
    func testMarkingANoteGenuineAddsItToTheEnrolment() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (coordinator, db, config, fingerprints) = try await enrolled()
        let jid = try XCTUnwrap(fingerprints.first?.jid)

        let store = try ChatStore.open(url: config.locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store).filter {
            $0.senderJID == jid && !$0.isFromMe && $0.durationSeconds >= 3
                && FileManager.default.fileExists(atPath: config.locator.mediaURL(relativePath: $0.relativeMediaPath).path)
        }
        let enrolledPKs = Set(try db.enrollmentNotes(jid: jid).map(\.messagePK))
        let candidate = try XCTUnwrap(notes.first { !enrolledPKs.contains($0.messagePK) } ?? notes.first)

        _ = try await coordinator.verify(candidate)
        try await coordinator.markGenuine(messagePK: candidate.messagePK)

        let after = try db.enrollmentNotes(jid: jid)
        XCTAssertTrue(after.contains { $0.messagePK == candidate.messagePK })
        XCTAssertLessThanOrEqual(after.count, 30)
        XCTAssertEqual(try db.verdict(messagePK: candidate.messagePK)?.kind, VerdictKind.verified.rawValue)
        XCTAssertEqual(try db.verdict(messagePK: candidate.messagePK)?.reason, "userConfirmed")
    }

    /// Reporting an impostor has to remove their influence entirely: no fingerprint, no enrolment,
    /// and they stay out of the next enrolment run.
    func testReportingAnImpostorRemovesThemCompletely() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (coordinator, db, config, fingerprints) = try await enrolled()
        let jid = try XCTUnwrap(fingerprints.first?.jid)

        let store = try ChatStore.open(url: config.locator.chatStorageURL)
        let note = try XCTUnwrap(try VoiceNoteQuery.fetch(store).last {
            $0.senderJID == jid && !$0.isFromMe
                && FileManager.default.fileExists(atPath: config.locator.mediaURL(relativePath: $0.relativeMediaPath).path)
        })
        _ = try await coordinator.verify(note)
        try await coordinator.reportImpostor(messagePK: note.messagePK)

        XCTAssertEqual(try db.contact(jid: jid)?.blacklisted, true)
        XCTAssertFalse(try db.fingerprints().contains { $0.jid == jid })
        XCTAssertTrue(try db.enrollmentNotes(jid: jid).isEmpty)
        XCTAssertEqual(try db.verdict(messagePK: note.messagePK)?.colour, VerdictColour.red.rawValue)

        let again = try await coordinator.enrollAll()
        XCTAssertFalse(again.contains { $0.jid == jid }, "a reported sender stays out of enrolment")
    }

    func testPinningPutsAContactAtTheFrontOfProtected() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (coordinator, db, _, fingerprints) = try await enrolled()
        let last = try XCTUnwrap(fingerprints.last?.jid)
        let protectedBefore = try await coordinator.protectedJIDs()
        try XCTSkipUnless(!protectedBefore.contains(last), "needs a contact outside the protected list")
        try await coordinator.setPinned(jid: last, true)
        let protectedAfter = try await coordinator.protectedJIDs()
        XCTAssertEqual(protectedAfter.first, last)
        XCTAssertEqual(try db.contact(jid: last)?.pinned, true)
    }
}
