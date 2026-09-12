import XCTest
@testable import AntiFishCore

final class VectorTests: XCTestCase {
    func testCosineOfIdenticalVectorsIsOne() {
        XCTAssertEqual(Vector.cosine([1, 2, 3], [1, 2, 3]), 1, accuracy: 1e-6)
    }

    func testCosineOfOrthogonalVectorsIsZero() {
        XCTAssertEqual(Vector.cosine([1, 0], [0, 1]), 0, accuracy: 1e-6)
    }

    func testCosineOfZeroVectorIsZero() {
        XCTAssertEqual(Vector.cosine([0, 0], [1, 1]), 0)
    }

    func testCosineOfMismatchedLengthsIsZero() {
        XCTAssertEqual(Vector.cosine([1, 0, 0], [1, 0]), 0)
        XCTAssertEqual(Vector.cosine([], []), 0)
    }

    func testNormalizedHasUnitLength() {
        XCTAssertEqual(Vector.normalized([3, 4]), [0.6, 0.8])
        XCTAssertEqual(Vector.normalized([0, 0]), [0, 0])
    }

    func testCentroidIsNormalizedMean() {
        let c = Vector.centroid([[1, 0], [0, 1]])
        XCTAssertEqual(c[0], c[1], accuracy: 1e-6)
        XCTAssertEqual(c.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1, accuracy: 1e-6)
    }

    func testCentroidOfNothingIsEmpty() {
        XCTAssertTrue(Vector.centroid([]).isEmpty)
    }

    func testDataRoundTrip() {
        let v: [Float] = [0.5, -1.25, 3]
        XCTAssertEqual(Vector.fromData(Vector.toData(v)), v)
        XCTAssertEqual(Vector.fromData(Data()), [])
    }
}
