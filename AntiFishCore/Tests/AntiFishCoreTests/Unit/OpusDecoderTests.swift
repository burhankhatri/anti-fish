import AVFoundation
import XCTest
@testable import AntiFishCore

final class OpusDecoderTests: XCTestCase {
    /// Writes a stereo 48 kHz sine to a CAF file so the decoder has something real to resample.
    private func writeTone(to url: URL, seconds: Double = 1, amplitude: Float = 0.5) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let v = Float(sin(2 * Double.pi * 1000 * Double(i) / 48_000)) * amplitude
            buffer.floatChannelData![0][i] = v
            buffer.floatChannelData![1][i] = v
        }
        try file.write(from: buffer)
    }

    func testMissingFileIsUnreadable() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("missing.opus")
        XCTAssertThrowsError(try OpusDecoder.decode(url: url)) { error in
            XCTAssertEqual(error as? AudioDecodeError, .unreadable("missing.opus"))
        }
    }

    func testGarbageFileIsUnreadable() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("junk.opus")
        try Data("not audio".utf8).write(to: url)
        XCTAssertThrowsError(try OpusDecoder.decode(url: url))
    }

    func testResamplesToSixteenKilohertzMono() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("tone.caf")
        try writeTone(to: url)
        let decoded = try OpusDecoder.decode(url: url)
        XCTAssertEqual(decoded.sampleRate, 16_000)
        XCTAssertEqual(decoded.seconds, 1.0, accuracy: 0.02)
        XCTAssertEqual(decoded.samples.count, decoded.samples.count)
        // RMS of a sine at amplitude 0.5 is 0.5/sqrt(2).
        XCTAssertEqual(decoded.rms, 0.5 / Float(2).squareRoot(), accuracy: 0.03)
    }

    func testLongerFileDecodesFully() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("long.caf")
        try writeTone(to: url, seconds: 12)
        let decoded = try OpusDecoder.decode(url: url)
        XCTAssertEqual(decoded.seconds, 12, accuracy: 0.05)
        XCTAssertGreaterThan(decoded.rms, 0.2)
    }

    func testSilenceHasZeroRMS() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("silent.caf")
        try writeTone(to: url, amplitude: 0)
        let decoded = try OpusDecoder.decode(url: url)
        XCTAssertEqual(decoded.rms, 0, accuracy: 1e-6)
    }
}
