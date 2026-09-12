import XCTest
@testable import AntiFishCore

/// A check on a shared image costs a network round trip and a slice of a paid quota. Losing the
/// answer when the app quits meant the same picture was judged again on every launch, and in
/// between it showed as unchecked — which reads as "nothing wrong here".
final class MediaVerdictStoreTests: XCTestCase {
    private func store() throws -> AppDatabase { try AppDatabase(url: nil) }

    func testAnImageVerdictSurvivesReopening() throws {
        let db = try store()
        let verdict = ImageVerdict.from(aiGenerated: 0.97, deepfake: 0.1)
        try db.saveImageVerdict(verdict, messagePK: 42)

        let loaded = try db.imageVerdicts()
        XCTAssertEqual(loaded[42]?.kind, .aiGenerated)
        XCTAssertEqual(loaded[42]?.aiGenerated ?? 0, 0.97, accuracy: 0.0001)
    }

    /// "Looks real" has to persist too, or a clean picture is re-uploaded forever.
    func testAClearImageIsRememberedAsClear() throws {
        let db = try store()
        try db.saveImageVerdict(ImageVerdict.from(aiGenerated: 0.02, deepfake: 0.01), messagePK: 7)
        XCTAssertEqual(try db.imageVerdicts()[7]?.kind, .authentic)
    }

    func testAVideoVerdictSurvivesReopening() throws {
        let db = try store()
        let verdict = VideoVerdict.from(peakAI: 0.9, peakDeepfake: 0.2, framesChecked: 5, framesFlagged: 4)
        try db.saveVideoVerdict(verdict, messagePK: 9)

        let loaded = try db.videoVerdicts()
        XCTAssertEqual(loaded[9]?.image.kind, .aiGenerated)
        XCTAssertEqual(loaded[9]?.framesFlagged, 4)
    }

    /// Re-running a check replaces the old answer rather than failing or duplicating it.
    func testRecheckingReplacesTheStoredAnswer() throws {
        let db = try store()
        try db.saveImageVerdict(ImageVerdict.from(aiGenerated: 0.01, deepfake: 0.01), messagePK: 3)
        try db.saveImageVerdict(ImageVerdict.from(aiGenerated: 0.99, deepfake: 0.01), messagePK: 3)
        XCTAssertEqual(try db.imageVerdicts()[3]?.kind, .aiGenerated)
        XCTAssertEqual(try db.imageVerdicts().count, 1)
    }

    /// Images and videos share a table; one must not overwrite the other at the same key.
    func testImageAndVideoAnswersDoNotCollide() throws {
        let db = try store()
        try db.saveImageVerdict(ImageVerdict.from(aiGenerated: 0.99, deepfake: 0.0), messagePK: 5)
        try db.saveVideoVerdict(VideoVerdict.from(peakAI: 0.0, peakDeepfake: 0.0,
                                                  framesChecked: 5, framesFlagged: 0), messagePK: 5)
        XCTAssertEqual(try db.imageVerdicts()[5]?.kind, .aiGenerated)
        XCTAssertEqual(try db.videoVerdicts()[5]?.image.kind, .authentic)
    }
}
