import XCTest
@testable import AntiFishCore

/// Speaker embeddings from WeSpeaker are not zero-centred: any two utterances, same speaker or not,
/// score 0.65-0.90 against each other. Subtracting the cohort mean before comparing removes that
/// shared component. Measured on ten real speakers from this Mac: the gap between same-speaker and
/// different-speaker scores widened from 0.18 to 0.70.
final class EmbeddingCenterTests: XCTestCase {
    func testIdentityCenterLeavesVectorsAlone() {
        let center = EmbeddingCenter.identity
        XCTAssertTrue(center.isIdentity)
        XCTAssertEqual(center.project([0.6, 0.8]), [0.6, 0.8])
        XCTAssertEqual(center.score([1, 0], [1, 0]), 1, accuracy: 1e-6)
    }

    func testCenterOfNothingIsIdentity() {
        XCTAssertTrue(EmbeddingCenter(embeddings: []).isIdentity)
        XCTAssertTrue(EmbeddingCenter(mean: []).isIdentity)
    }

    func testMeanIsSubtractedAndResultRenormalised() {
        let center = EmbeddingCenter(embeddings: [[1, 0], [0, 1]])
        XCTAssertEqual(center.mean[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(center.mean[1], 0.5, accuracy: 1e-6)
        let projected = center.project([1, 0])
        XCTAssertEqual(projected[0], 0.5 / (0.5 * Float(2).squareRoot()), accuracy: 1e-5)
        XCTAssertEqual(projected.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1, accuracy: 1e-5)
    }

    /// The point of centering: two vectors that share a large common component look nearly
    /// identical raw, and clearly different once that shared part is removed.
    func testCenteringSeparatesVectorsThatShareABias() {
        let bias: [Float] = [1, 0, 0]
        let a = Vector.normalized(zip(bias, [0, 0.2, 0]).map(+))
        let b = Vector.normalized(zip(bias, [0, 0, 0.2]).map(+))
        XCTAssertGreaterThan(Vector.cosine(a, b), 0.9, "raw scores are dominated by the shared bias")

        let center = EmbeddingCenter(embeddings: [a, b])
        XCTAssertLessThan(center.score(a, b), 0.1, "centering exposes the actual difference")
    }

    func testProjectIgnoresVectorsOfTheWrongLength() {
        let center = EmbeddingCenter(embeddings: [[1, 0], [0, 1]])
        XCTAssertEqual(center.project([1, 0, 0]), [1, 0, 0])
        XCTAssertEqual(center.project([]), [])
    }

    func testScoreOfEmptyVectorIsZero() {
        let center = EmbeddingCenter(embeddings: [[1, 0], [0, 1]])
        XCTAssertEqual(center.score([], [1, 0]), 0)
    }

    func testRoundTripsThroughData() {
        let center = EmbeddingCenter(embeddings: [[1, 0], [0, 1]])
        let restored = EmbeddingCenter(mean: Vector.fromData(Vector.toData(center.mean)))
        XCTAssertEqual(restored.mean, center.mean)
        XCTAssertFalse(restored.isIdentity)
    }

    func testCentroidIsComputedInProjectedSpace() {
        let center = EmbeddingCenter(embeddings: [[1, 0], [0, 1]])
        let c = center.centroid(of: [[1, 0], [1, 0]])
        XCTAssertEqual(Vector.cosine(c, center.project([1, 0])), 1, accuracy: 1e-5)
    }
}
