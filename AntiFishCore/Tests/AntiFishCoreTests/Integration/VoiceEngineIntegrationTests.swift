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

    /// The heart of the product: two notes from the same person must score higher against each
    /// other than against notes from anyone else. Uses this Mac's real voice notes.
    func testSameSpeakerScoresHigherThanDifferentSpeakers() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let (locator, notes) = try incomingNotes(minDuration: 4)
        let bySender = Dictionary(grouping: notes, by: \.senderJID).filter { $0.value.count >= 2 }
        let senders = Array(bySender.keys.sorted().prefix(6))
        try XCTSkipUnless(senders.count >= 3, "needs at least three senders with two notes each")

        let engine = try engine()
        var embeddings: [String: [[Float]]] = [:]
        for sender in senders {
            for note in bySender[sender]!.suffix(2) {
                let analysis = try await engine.analyze(url: locator.mediaURL(relativePath: note.relativeMediaPath))
                guard !analysis.embedding.isEmpty else { continue }
                embeddings[sender, default: []].append(analysis.embedding)
            }
        }
        let usable = embeddings.filter { $0.value.count >= 2 }
        XCTAssertGreaterThanOrEqual(usable.count, 3)

        var same: [Float] = []
        var different: [Float] = []
        for (sender, vectors) in usable {
            same.append(Vector.cosine(vectors[0], vectors[1]))
            for (other, otherVectors) in usable where other != sender {
                different.append(Vector.cosine(vectors[0], otherVectors[0]))
            }
        }
        let sameMean = same.reduce(0, +) / Float(same.count)
        let differentMean = different.reduce(0, +) / Float(different.count)
        XCTAssertGreaterThan(sameMean, differentMean + 0.15,
                             "same-speaker mean \(sameMean) vs different-speaker mean \(differentMean)")
        XCTAssertGreaterThan(same.min() ?? 0, different.max() ?? 1,
                             "worst same-speaker pair should still beat the best impostor pair")
    }
}
