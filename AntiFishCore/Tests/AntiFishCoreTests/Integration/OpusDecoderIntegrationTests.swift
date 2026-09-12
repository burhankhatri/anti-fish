import XCTest
@testable import AntiFishCore

final class OpusDecoderIntegrationTests: XCTestCase {
    /// WhatsApp voice notes are Ogg-Opus at 48 kHz mono. AVFoundation decodes them natively on
    /// this macOS; this proves it against a real note rather than a synthetic file.
    func testRealVoiceNoteDecodes() throws {
        try TestEnv.skipUnlessRealWA()
        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let note = try XCTUnwrap(try VoiceNoteQuery.fetch(store).last { note in
            !note.isFromMe && note.durationSeconds >= 3
                && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: note.relativeMediaPath).path)
        })
        let decoded = try OpusDecoder.decode(url: locator.mediaURL(relativePath: note.relativeMediaPath))
        XCTAssertEqual(decoded.sampleRate, 16_000)
        XCTAssertGreaterThan(decoded.rms, 0.01, "decoded audio should not be silence")
        let expected = Double(note.durationSeconds)
        XCTAssertGreaterThan(decoded.seconds, expected * 0.7)
        XCTAssertLessThan(decoded.seconds, expected * 1.3 + 1)
    }

    func testEveryRecentVoiceNoteDecodes() throws {
        try TestEnv.skipUnlessRealWA()
        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store)
            .filter { !$0.isFromMe && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: $0.relativeMediaPath).path) }
            .suffix(25)
        XCTAssertGreaterThan(notes.count, 0)
        for note in notes {
            let decoded = try OpusDecoder.decode(url: locator.mediaURL(relativePath: note.relativeMediaPath))
            XCTAssertGreaterThan(decoded.samples.count, 0, "message \(note.messagePK) decoded to nothing")
        }
    }
}
