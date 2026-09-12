import XCTest
@testable import AntiFishCore

/// A video is checked by checking frames inside it. Measured on five labelled clips:
/// five frames spread across the clip got all five right; three frames from the opening
/// called a real selfie AI-generated at 0.99. Sampling position matters more than count.
final class VideoCheckTests: XCTestCase {
    func testDisabledWithoutCredentials() throws {
        let script = try TestEnv.tempDir().appendingPathComponent("videobridge.py")
        try Data("#!/usr/bin/env python3\n".utf8).write(to: script)
        let check = VideoCheck(credentials: nil, scriptURL: script)
        XCTAssertFalse(check.isConfigured)
        XCTAssertTrue(check.unavailableReason.contains("SightEngine"))
    }

    func testConfiguredWithBoth() throws {
        let script = try TestEnv.tempDir().appendingPathComponent("videobridge.py")
        try Data("#!/usr/bin/env python3\n".utf8).write(to: script)
        let check = VideoCheck(credentials: .init(user: "u", secret: "s"), scriptURL: script)
        XCTAssertTrue(check.isConfigured)
    }

    /// The strongest frame decides: a clip only has to be generated somewhere to be generated.
    func testTheStrongestFrameDecides() {
        let verdict = VideoVerdict.from(peakAI: 0.99, peakDeepfake: 0.01,
                                        framesChecked: 5, framesFlagged: 5)
        XCTAssertEqual(verdict.image.kind, .aiGenerated)
        XCTAssertEqual(verdict.framesChecked, 5)
        XCTAssertEqual(verdict.framesFlagged, 5)
        XCTAssertTrue(verdict.isAlarming)
    }

    func testASingleFlaggedFrameIsStillAFlag() {
        let verdict = VideoVerdict.from(peakAI: 0.02, peakDeepfake: 0.88,
                                        framesChecked: 5, framesFlagged: 1)
        XCTAssertEqual(verdict.image.kind, .faceSwapped)
        XCTAssertTrue(verdict.isAlarming)
    }

    func testACleanClipIsAuthentic() {
        let verdict = VideoVerdict.from(peakAI: 0.14, peakDeepfake: 0.01,
                                        framesChecked: 5, framesFlagged: 0)
        XCTAssertEqual(verdict.image.kind, .authentic)
        XCTAssertFalse(verdict.isAlarming)
    }

    /// How many frames agreed is what a person should be told, not a raw score.
    func testSummaryNamesTheEvidence() {
        let flagged = VideoVerdict.from(peakAI: 0.99, peakDeepfake: 0,
                                        framesChecked: 5, framesFlagged: 4)
        XCTAssertEqual(flagged.summary, "4 of 5 frames look generated")
        let clean = VideoVerdict.from(peakAI: 0.01, peakDeepfake: 0,
                                      framesChecked: 5, framesFlagged: 0)
        XCTAssertEqual(clean.summary, "none of 5 frames look generated")
    }
}
