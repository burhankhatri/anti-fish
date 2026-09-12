import XCTest
@testable import AntiFishCore

/// Enrolment ran once, when the store was empty. Anyone who started sending voice notes after
/// that never got a baseline, so they could not be verified and never appeared in the list of
/// people a caller might claim to be.
final class NewcomerEnrolmentIntegrationTests: XCTestCase {
    private func coordinator() throws -> (Coordinator, AppDatabase, CoordinatorConfig) {
        let config = CoordinatorConfig(locator: ContainerLocator(),
                                       models: ModelPaths(directory: TestEnv.modelsDir))
        let db = try AppDatabase(url: nil)
        return (Coordinator(config: config, db: db,
                            engine: try VoiceEngine(models: config.models, numThreads: 4)),
                db, config)
    }

    func testSomeoneWhoBecomesEligibleLaterIsEnrolled() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (coordinator, db, _) = try coordinator()

        let first = try await coordinator.enrollAll()
        XCTAssertGreaterThan(first.count, 5)

        // Simulate the state the app was in: someone eligible, but with no fingerprint yet,
        // because enrolment happened before their notes arrived.
        let dropped = try XCTUnwrap(first.last?.jid)
        try db.saveFingerprints(try db.fingerprints().filter { $0.jid != dropped })
        try db.replaceEnrollment(jid: dropped, notes: [])
        XCTAssertFalse(try db.fingerprints().contains { $0.jid == dropped })

        let added = try await coordinator.enrollNewcomers()
        XCTAssertTrue(added.contains(dropped), "they should have been picked up")
        XCTAssertTrue(try db.fingerprints().contains { $0.jid == dropped })
    }

    /// Running it when nobody new qualifies must not disturb the baselines already built.
    func testRunningItAgainChangesNothing() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (coordinator, db, _) = try coordinator()
        _ = try await coordinator.enrollAll()
        let before = try db.fingerprints()

        let added = try await coordinator.enrollNewcomers()
        XCTAssertTrue(added.isEmpty)
        XCTAssertEqual(try db.fingerprints().count, before.count)
    }

    /// The centre of the embedding space must not move, or every existing baseline becomes
    /// incomparable with the scores already stored against it.
    func testTheEmbeddingCentreIsLeftAlone() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (coordinator, db, _) = try coordinator()
        _ = try await coordinator.enrollAll()
        let centre = try db.embeddingCenter()

        let dropped = try XCTUnwrap(try db.fingerprints().last?.jid)
        try db.saveFingerprints(try db.fingerprints().filter { $0.jid != dropped })
        try db.replaceEnrollment(jid: dropped, notes: [])
        _ = try await coordinator.enrollNewcomers()

        XCTAssertEqual(try db.embeddingCenter(), centre)
    }
}
