import XCTest
@testable import AntiFishCore

final class SpeechTrimmerTests: XCTestCase {
    func testMissingModelThrows() {
        XCTAssertThrowsError(try SpeechTrimmer(modelPath: "/nonexistent/silero_vad.onnx")) { error in
            XCTAssertEqual(error as? VoiceEngineError, .modelMissing("/nonexistent/silero_vad.onnx"))
        }
    }

    func testSilenceYieldsNoSpeech() throws {
        try TestEnv.skipUnlessModels()
        let trimmer = try SpeechTrimmer(modelPath: TestEnv.vadModelPath)
        let trimmed = trimmer.trim([Float](repeating: 0, count: 3 * SpeechTrimmer.sampleRate))
        XCTAssertEqual(trimmed.speechSeconds, 0)
        XCTAssertTrue(trimmed.samples.isEmpty)
    }

    func testEmptyInputIsSafe() throws {
        try TestEnv.skipUnlessModels()
        let trimmer = try SpeechTrimmer(modelPath: TestEnv.vadModelPath)
        XCTAssertEqual(trimmer.trim([]).speechSeconds, 0)
    }

    func testTrimmerIsReusableAcrossCalls() throws {
        try TestEnv.skipUnlessModels()
        let trimmer = try SpeechTrimmer(modelPath: TestEnv.vadModelPath)
        let silence = [Float](repeating: 0, count: SpeechTrimmer.sampleRate)
        XCTAssertEqual(trimmer.trim(silence).speechSeconds, 0)
        XCTAssertEqual(trimmer.trim(silence).speechSeconds, 0)
    }
}
