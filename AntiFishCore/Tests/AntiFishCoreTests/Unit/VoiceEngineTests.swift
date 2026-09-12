import XCTest
@testable import AntiFishCore

final class VoiceEngineTests: XCTestCase {
    func testModelPathsFromDirectory() {
        let paths = ModelPaths(directory: URL(fileURLWithPath: "/m"))
        XCTAssertEqual(paths.speakerModel, "/m/wespeaker_en_voxceleb_resnet34_LM.onnx")
        XCTAssertEqual(paths.vadModel, "/m/silero_vad.onnx")
    }

    func testMissingModelsFailToConstruct() {
        XCTAssertThrowsError(try VoiceEngine(models: ModelPaths(directory: URL(fileURLWithPath: "/nope"))))
    }

    func testSilenceProducesNoEmbedding() async throws {
        try TestEnv.skipUnlessModels()
        let engine = try VoiceEngine(models: ModelPaths(directory: TestEnv.modelsDir))
        let analysis = try await engine.analyze(samples: [Float](repeating: 0, count: 2 * 16_000))
        XCTAssertTrue(analysis.embedding.isEmpty, "silence must not produce a voice fingerprint")
        XCTAssertEqual(analysis.speechSeconds, 0)
        XCTAssertEqual(analysis.totalSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(engine.modelVersion, "wespeaker_en_voxceleb_resnet34_LM")
    }

    func testUnreadableFileThrows() async throws {
        try TestEnv.skipUnlessModels()
        let engine = try VoiceEngine(models: ModelPaths(directory: TestEnv.modelsDir))
        let url = try TestEnv.tempDir().appendingPathComponent("missing.opus")
        do {
            _ = try await engine.analyze(url: url)
            XCTFail("expected a decode error")
        } catch {
            XCTAssertEqual(error as? AudioDecodeError, .unreadable("missing.opus"))
        }
    }
}
