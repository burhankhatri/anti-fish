import XCTest
@testable import AntiFishCore

final class SpeechTrimmerIntegrationTests: XCTestCase {
    func testRealVoiceNoteKeepsMostOfItsSpeech() throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let note = try XCTUnwrap(try VoiceNoteQuery.fetch(store).last { note in
            !note.isFromMe && note.durationSeconds >= 5
                && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: note.relativeMediaPath).path)
        })
        let decoded = try OpusDecoder.decode(url: locator.mediaURL(relativePath: note.relativeMediaPath))
        let trimmed = try SpeechTrimmer(modelPath: TestEnv.vadModelPath).trim(decoded.samples)
        XCTAssertGreaterThan(trimmed.speechSeconds, Double(note.durationSeconds) * 0.3,
                             "a spoken note should be mostly speech")
        XCTAssertLessThanOrEqual(trimmed.speechSeconds, decoded.seconds * 1.2)
        XCTAssertEqual(trimmed.samples.count, Int(trimmed.speechSeconds * 16_000), accuracy: 16_000)
    }
}
