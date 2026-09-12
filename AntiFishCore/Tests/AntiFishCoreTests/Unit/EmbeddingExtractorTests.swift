import XCTest
@testable import AntiFishCore

final class EmbeddingExtractorTests: XCTestCase {
    /// A harmonic tone stands in for a voice: deterministic, and no personal audio in the repo.
    private func tone(hz: Double, seconds: Double = 2) -> [Float] {
        let n = Int(seconds * Double(SherpaEmbeddingExtractor.sampleRate))
        return (0..<n).map { i in
            let t = Double(i) / Double(SherpaEmbeddingExtractor.sampleRate)
            return Float(0.3 * sin(2 * .pi * hz * t)
                       + 0.15 * sin(2 * .pi * 2 * hz * t)
                       + 0.05 * sin(2 * .pi * 3 * hz * t))
        }
    }

    func testMissingModelThrows() {
        XCTAssertThrowsError(try SherpaEmbeddingExtractor(modelPath: "/nonexistent/model.onnx")) { error in
            XCTAssertEqual(error as? VoiceEngineError, .modelMissing("/nonexistent/model.onnx"))
        }
    }

    func testEmbeddingIs256DimensionalAndUnitLength() throws {
        try TestEnv.skipUnlessModels()
        let extractor = try SherpaEmbeddingExtractor(modelPath: TestEnv.speakerModelPath)
        XCTAssertEqual(extractor.dimension, 256)
        XCTAssertEqual(extractor.modelVersion, "wespeaker_en_voxceleb_resnet34_LM")
        let e = try extractor.embed(tone(hz: 180))
        XCTAssertEqual(e.count, 256)
        XCTAssertEqual(e.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1, accuracy: 1e-4)
    }

    func testSameInputGivesTheSameEmbedding() throws {
        try TestEnv.skipUnlessModels()
        let extractor = try SherpaEmbeddingExtractor(modelPath: TestEnv.speakerModelPath)
        let a = try extractor.embed(tone(hz: 180))
        let b = try extractor.embed(tone(hz: 180))
        XCTAssertEqual(Vector.cosine(a, b), 1, accuracy: 1e-4)
    }

    func testDifferentSignalsGiveDifferentEmbeddings() throws {
        try TestEnv.skipUnlessModels()
        let extractor = try SherpaEmbeddingExtractor(modelPath: TestEnv.speakerModelPath)
        let a = try extractor.embed(tone(hz: 120))
        let b = try extractor.embed(tone(hz: 260))
        XCTAssertLessThan(Vector.cosine(a, b), 0.999)
    }

    func testEmptyInputFails() throws {
        try TestEnv.skipUnlessModels()
        let extractor = try SherpaEmbeddingExtractor(modelPath: TestEnv.speakerModelPath)
        XCTAssertThrowsError(try extractor.embed([])) { error in
            XCTAssertEqual(error as? VoiceEngineError, .embeddingFailed)
        }
    }
}
