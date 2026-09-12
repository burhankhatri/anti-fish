import XCTest
@testable import AntiFishCore

final class VoiceEngineIntegrationTests: XCTestCase {
    private func engine() throws -> VoiceEngine {
        try VoiceEngine(models: ModelPaths(directory: TestEnv.modelsDir), numThreads: 4)
    }

    private func incomingNotes(minDuration: Int = 3) throws -> (ContainerLocator, [VoiceNoteRecord]) {
        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store).filter {
            !$0.isFromMe && !$0.senderJID.isEmpty && !$0.senderJID.hasPrefix("status@")
                && $0.durationSeconds >= minDuration
                && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: $0.relativeMediaPath).path)
        }
        return (locator, notes)
    }

    func testRealVoiceNoteProducesAnEmbedding() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (locator, notes) = try incomingNotes()
        let note = try XCTUnwrap(notes.last)
        let analysis = try await engine().analyze(url: locator.mediaURL(relativePath: note.relativeMediaPath))
        XCTAssertEqual(analysis.embedding.count, 256)
        XCTAssertGreaterThan(analysis.speechSeconds, 0.5)
        XCTAssertLessThanOrEqual(analysis.speechSeconds, analysis.totalSeconds + 0.01)
    }

    /// The engine's own contract: every real note with speech in it yields a usable fingerprint.
    /// How well those fingerprints separate speakers is asserted by
    /// `EmbeddingSeparationIntegrationTests`, which measures ten speakers in both scoring spaces.
    func testEveryUsableNoteYieldsAWellFormedEmbedding() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (locator, notes) = try incomingNotes(minDuration: 4)
        let sample = Array(notes.suffix(12))
        XCTAssertGreaterThan(sample.count, 0)

        let engine = try engine()
        var withSpeech = 0
        for note in sample {
            let a = try await engine.analyze(url: locator.mediaURL(relativePath: note.relativeMediaPath))
            XCTAssertLessThanOrEqual(a.speechSeconds, a.totalSeconds + 0.01)
            guard a.speechSeconds >= VoiceEngine.minSpeechSecondsForEmbedding else {
                XCTAssertTrue(a.embedding.isEmpty, "no speech must mean no fingerprint")
                continue
            }
            withSpeech += 1
            XCTAssertEqual(a.embedding.count, 256, "message \(note.messagePK)")
            XCTAssertEqual(a.embedding.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1, accuracy: 1e-4)
        }
        XCTAssertGreaterThan(withSpeech, sample.count / 2, "most real voice notes should contain speech")
    }
}
