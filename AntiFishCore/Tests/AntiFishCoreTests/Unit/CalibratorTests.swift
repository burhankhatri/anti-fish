import XCTest
@testable import AntiFishCore

final class CalibratorTests: XCTestCase {
    /// Synthetic speakers in 6 dimensions: speaker i points along axis i with a per-note lean
    /// toward axis i+1, so same-speaker pairs score near 1 and different speakers score low.
    private func notes(speakers: Int, notesEach: Int = 4) -> [EnrolledNote] {
        (0..<speakers).flatMap { i in
            (0..<notesEach).map { k in
                var v = [Float](repeating: 0, count: 6)
                v[i % 6] = 1
                v[(i + 1) % 6] = 0.1 * Float(k + 1)
                return EnrolledNote(jid: "s\(i)@lid", messagePK: Int64(i * 10 + k),
                                    embedding: Vector.normalized(v), speechSeconds: 10,
                                    date: Date(timeIntervalSinceReferenceDate: 1_000 + Double(k)))
            }
        }
    }

    func testPercentileUsesNearestRank() {
        let v: [Float] = [5, 1, 4, 2, 3]
        XCTAssertEqual(Calibrator.percentile(v, 0), 1)
        XCTAssertEqual(Calibrator.percentile(v, 50), 3)
        XCTAssertEqual(Calibrator.percentile(v, 100), 5)
        XCTAssertEqual(Calibrator.percentile([], 50), 0)
    }

    func testWellSeparatedSpeakersProduceCalibratedThresholds() {
        let result = Calibrator.calibrate(notes: notes(speakers: 6), center: .identity,
                                          now: Date(timeIntervalSinceReferenceDate: 5))
        XCTAssertTrue(result.thresholds.calibrated)
        XCTAssertEqual(result.contactCount, 6)
        XCTAssertEqual(result.genuineCount, 24)
        XCTAssertEqual(result.impostorCount, 24 * 5)
        XCTAssertLessThan(result.thresholds.reject, result.thresholds.match)
        XCTAssertGreaterThan(result.genuineMedian, result.impostorMedian)
        XCTAssertEqual(result.calibratedAt, Date(timeIntervalSinceReferenceDate: 5))
    }

    func testTooFewContactsKeepsTheMeasuredDefaults() {
        let result = Calibrator.calibrate(notes: notes(speakers: 4), center: .identity)
        XCTAssertEqual(result.thresholds, Thresholds())
        XCTAssertFalse(result.thresholds.calibrated)
        XCTAssertEqual(result.contactCount, 4)
    }

    func testContactsWithTooFewNotesAreExcluded() {
        var all = notes(speakers: 5)
        all.append(EnrolledNote(jid: "thin@lid", messagePK: 999, embedding: [1, 0, 0, 0, 0, 0],
                                speechSeconds: 5, date: Date()))
        XCTAssertEqual(Calibrator.calibrate(notes: all, center: .identity).contactCount, 5)
    }

    /// Thresholds must stay ordered and inside the valid cosine range even when the two
    /// distributions overlap, which happens when two JIDs belong to the same person.
    func testOverlappingDistributionsStillProduceUsableThresholds() {
        let overlapping = (0..<6).flatMap { i in
            (0..<4).map { k in
                var v = [Float](repeating: 0.4, count: 6)
                v[i % 6] = 1
                v[(i + 1) % 6] = 0.05 * Float(k)
                return EnrolledNote(jid: "s\(i)@lid", messagePK: Int64(i * 10 + k),
                                    embedding: Vector.normalized(v), speechSeconds: 10, date: Date())
            }
        }
        let result = Calibrator.calibrate(notes: overlapping, center: .identity)
        XCTAssertLessThan(result.thresholds.reject, result.thresholds.match)
        XCTAssertGreaterThanOrEqual(result.thresholds.reject, -1)
        XCTAssertLessThanOrEqual(result.thresholds.match, 1)
    }

    func testCalibrationHappensInTheCentredSpace() {
        let raw = notes(speakers: 6)
        let center = EmbeddingCenter(embeddings: raw.map(\.embedding))
        let centred = Calibrator.calibrate(notes: raw, center: center)
        let plain = Calibrator.calibrate(notes: raw, center: .identity)
        XCTAssertNotEqual(centred.genuineMedian, plain.genuineMedian)
        XCTAssertGreaterThan(centred.genuineMedian - centred.impostorMedian,
                             plain.genuineMedian - plain.impostorMedian)
    }

    func testNoNotesIsSafe() {
        let result = Calibrator.calibrate(notes: [], center: .identity)
        XCTAssertEqual(result.contactCount, 0)
        XCTAssertEqual(result.thresholds, Thresholds())
    }
}
