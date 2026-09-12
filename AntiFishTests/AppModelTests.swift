import XCTest
import AntiFishCore
@testable import AntiFish

@MainActor
final class AppModelTests: XCTestCase {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("antifish-app-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func containerWithDatabase() throws -> URL {
        let root = try tempDir()
        try Data("x".utf8).write(to: root.appendingPathComponent("ChatStorage.sqlite"))
        return root
    }

    // MARK: Phases

    func testEmptyContainerNeedsWhatsApp() async throws {
        let model = AppModel(locator: ContainerLocator(root: try tempDir()), databaseURL: nil)
        await model.start()
        XCTAssertEqual(model.phase, .needsWhatsApp)
    }

    func testUnreadableDatabaseNeedsFullDiskAccess() async throws {
        let root = try containerWithDatabase()
        let db = root.appendingPathComponent("ChatStorage.sqlite")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: db.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: db.path) }

        let model = AppModel(locator: ContainerLocator(root: root), databaseURL: nil)
        await model.start()
        XCTAssertEqual(model.phase, .needsFullDiskAccess)
    }

    func testReadableContainerReachesSetup() async throws {
        let model = AppModel(locator: ContainerLocator(root: try containerWithDatabase()), databaseURL: nil)
        await model.start()
        XCTAssertEqual(model.phase, .setupChoices)
    }

    // MARK: Projections

    func testFeedItemReadsItsVerdict() {
        let note = VoiceNoteRecord(messagePK: 1, chatJID: "a@lid", senderJID: "a@lid", isFromMe: false,
                                   date: Date(), durationSeconds: 3, relativeMediaPath: "Media/a/x.opus",
                                   chatIsGroup: false)
        let verdict = Verdict(kind: .takeoverSuspected, colour: .red, comparedJID: "a@lid", score: 0.1,
                              best: nil, reason: nil, explanation: "x")
        let item = FeedItem(record: VerdictRecord(note: note, verdict: verdict, speechSeconds: 3,
                                                  computedAt: Date(), modelVersion: "m"),
                            senderName: "Abdul", chatName: nil, avatarURL: nil)
        XCTAssertEqual(item.kind, .takeoverSuspected)
        XCTAssertEqual(item.colour, .red)
        XCTAssertTrue(item.needsAttention)
        XCTAssertEqual(item.id, 1)
    }

    /// Most rows should carry no pill at all: absence is the ordinary state.
    func testOnlyNotableVerdictsShowAPill() {
        XCTAssertFalse(FeedItem.showsPill(for: .unknownVoice))
        XCTAssertFalse(FeedItem.showsPill(for: .unverifiable))
        XCTAssertTrue(FeedItem.showsPill(for: .verified))
        XCTAssertTrue(FeedItem.showsPill(for: .takeoverSuspected))
        XCTAssertTrue(FeedItem.showsPill(for: .impersonationSuspected))
        XCTAssertTrue(FeedItem.showsPill(for: .matchesUnsavedNumber))
    }

    func testContactRowsSortProtectedFirstThenRecency() {
        let old = Date(timeIntervalSinceReferenceDate: 1)
        let new = Date(timeIntervalSinceReferenceDate: 2)
        let rows = [
            ContactRow(jid: "e@lid", name: "E", isSaved: true, pinned: false, noteCount: 3,
                       speechSeconds: 40, lastNoteDate: new, tier: .enrolled, avatarURL: nil),
            ContactRow(jid: "p1@lid", name: "P1", isSaved: true, pinned: false, noteCount: 3,
                       speechSeconds: 40, lastNoteDate: old, tier: .protected, avatarURL: nil),
            ContactRow(jid: "n@lid", name: "N", isSaved: false, pinned: false, noteCount: 1,
                       speechSeconds: 5, lastNoteDate: nil, tier: .needsVoice, avatarURL: nil),
            ContactRow(jid: "p2@lid", name: "P2", isSaved: true, pinned: false, noteCount: 3,
                       speechSeconds: 40, lastNoteDate: new, tier: .protected, avatarURL: nil),
        ]
        XCTAssertEqual(AppModel.sorted(rows).map(\.jid), ["p2@lid", "p1@lid", "e@lid", "n@lid"])
    }

    func testPinnedContactsFloatToTheTopOfTheirTier() {
        let when = Date(timeIntervalSinceReferenceDate: 1)
        let rows = [
            ContactRow(jid: "a@lid", name: "A", isSaved: true, pinned: false, noteCount: 3,
                       speechSeconds: 40, lastNoteDate: Date(), tier: .protected, avatarURL: nil),
            ContactRow(jid: "b@lid", name: "B", isSaved: true, pinned: true, noteCount: 3,
                       speechSeconds: 40, lastNoteDate: when, tier: .protected, avatarURL: nil),
        ]
        XCTAssertEqual(AppModel.sorted(rows).map(\.jid), ["b@lid", "a@lid"])
    }

    // MARK: Score meter maths

    func testMeterPlacesTheScoreBetweenTheThresholds() {
        let t = Thresholds(reject: 0.2, match: 0.6)
        XCTAssertEqual(ScoreMeter.band(for: 0.1, thresholds: t), .mismatch)
        XCTAssertEqual(ScoreMeter.band(for: 0.4, thresholds: t), .inconclusive)
        XCTAssertEqual(ScoreMeter.band(for: 0.8, thresholds: t), .match)
        XCTAssertEqual(ScoreMeter.band(for: 0.2, thresholds: t), .mismatch, "the edge belongs to mismatch")
        XCTAssertEqual(ScoreMeter.band(for: 0.6, thresholds: t), .match, "the edge belongs to match")
    }

    /// Thresholds are learned, so they can be negative. The meter still has to place them.
    func testMeterHandlesNegativeThresholds() {
        let t = Thresholds(reject: -0.03, match: 0.63, calibrated: true)
        XCTAssertEqual(ScoreMeter.position(of: -1, thresholds: t), 0, accuracy: 0.001)
        XCTAssertEqual(ScoreMeter.position(of: 1, thresholds: t), 1, accuracy: 0.001)
        XCTAssertEqual(ScoreMeter.position(of: 0, thresholds: t), 0.5, accuracy: 0.001)
        let rejectAt = ScoreMeter.position(of: t.reject, thresholds: t)
        let matchAt = ScoreMeter.position(of: t.match, thresholds: t)
        XCTAssertLessThan(rejectAt, matchAt)
        XCTAssertGreaterThan(rejectAt, 0)
        XCTAssertLessThan(matchAt, 1)
    }

    func testMeterClampsOutOfRangeScores() {
        let t = Thresholds()
        XCTAssertEqual(ScoreMeter.position(of: -5, thresholds: t), 0)
        XCTAssertEqual(ScoreMeter.position(of: 5, thresholds: t), 1)
    }
}
