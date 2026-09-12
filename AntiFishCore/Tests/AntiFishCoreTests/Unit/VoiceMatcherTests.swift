import XCTest
@testable import AntiFishCore

/// How a note is scored against a contact.
///
/// Comparing only to the centroid loses information: a voice varies between notes, and the
/// centroid averages that variation away. Measured on 28 real contacts (383 genuine comparisons
/// against 10,341 impostor ones), blending the centroid with the best three individual notes cut
/// the error rate from 12.7% to 10.4%.
final class VoiceMatcherTests: XCTestCase {
    private let a: [Float] = [1, 0, 0]
    private let b: [Float] = [0, 1, 0]

    func testScoreWithNoEnrolledNotesFallsBackToTheCentroid() {
        let score = VoiceMatcher.score(probe: a, centroid: a, noteEmbeddings: [])
        XCTAssertEqual(score, 1, accuracy: 1e-5)
    }

    func testScoreBlendsTheCentroidWithTheClosestNotes() {
        // The centroid sits between two very different notes, so it matches neither well.
        // One of the notes is an exact match, and the blend should reflect that.
        let far: [Float] = [0, 0, 1]
        let centroid = Vector.centroid([a, far])
        let centroidOnly = Vector.cosine(a, centroid)
        let blended = VoiceMatcher.score(probe: a, centroid: centroid, noteEmbeddings: [a, far])
        XCTAssertGreaterThan(blended, centroidOnly, "matching one real note should count for something")
        XCTAssertLessThan(blended, 1, "but it should not ignore the centroid either")
    }

    func testAStrangerScoresLowAgainstEveryNote() {
        XCTAssertLessThan(VoiceMatcher.score(probe: b, centroid: a, noteEmbeddings: [a, a, a]), 0.1)
    }

    func testOnlyTheBestFewNotesCount() {
        // Twenty poor matches should not drown out the three good ones.
        let notes = [a, a, a] + Array(repeating: b, count: 20)
        XCTAssertGreaterThan(VoiceMatcher.score(probe: a, centroid: a, noteEmbeddings: notes), 0.9)
    }

    func testEmptyProbeScoresZero() {
        XCTAssertEqual(VoiceMatcher.score(probe: [], centroid: a, noteEmbeddings: [a]), 0)
    }
}

/// Calibration learns one number: the point where wrongly clearing a stranger and wrongly
/// flagging a friend happen equally often. One number means every note gets an answer.
final class DecisionThresholdTests: XCTestCase {
    func testEqualErrorThresholdSitsBetweenTheTwoDistributions() {
        let genuine: [Float] = [0.5, 0.6, 0.7, 0.8, 0.9]
        let impostor: [Float] = [-0.2, -0.1, 0.0, 0.1, 0.2]
        let t = Calibrator.equalErrorThreshold(genuine: genuine, impostor: impostor)
        XCTAssertGreaterThan(t, 0.2)
        XCTAssertLessThan(t, 0.5)
    }

    func testThresholdWithNoDataKeepsTheDefault() {
        XCTAssertEqual(Calibrator.equalErrorThreshold(genuine: [], impostor: []), Thresholds().decision)
    }

    func testCalibrationProducesASingleDecisionPoint() {
        let notes = (0..<6).flatMap { i in
            (0..<4).map { k -> EnrolledNote in
                var v = [Float](repeating: 0, count: 6)
                v[i % 6] = 1
                v[(i + 1) % 6] = 0.1 * Float(k + 1)
                return EnrolledNote(jid: "s\(i)@lid", messagePK: Int64(i * 10 + k),
                                    embedding: Vector.normalized(v), speechSeconds: 10, date: Date())
            }
        }
        let result = Calibrator.calibrate(notes: notes, center: .identity)
        XCTAssertTrue(result.thresholds.calibrated)
        XCTAssertGreaterThan(result.thresholds.decision, -1)
        XCTAssertLessThan(result.thresholds.decision, 1)
        XCTAssertGreaterThanOrEqual(result.errorRate, 0)
        XCTAssertLessThanOrEqual(result.errorRate, 1)
    }
}
