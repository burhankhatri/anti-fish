import AVFoundation
import XCTest
@testable import AntiFishCore

/// `AVAudioFile.length` is an estimate for compressed formats. Real WhatsApp Ogg-Opus notes
/// over-declare their length by the codec's padding (960 frames / 20 ms was measured), and the
/// final read throws instead of returning zero frames. Reaching that point is the end of the
/// stream, not a broken file — but a file that yields nothing at all really is unreadable.
final class ChunkReaderTests: XCTestCase {
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    private func buffer(capacity: AVAudioFrameCount = 1024) -> AVAudioPCMBuffer {
        AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
    }

    private func drain(_ reader: ChunkReader) -> Int {
        var calls = 0
        var status = AVAudioConverterInputStatus.haveData
        while status == .haveData, calls < 100 {
            _ = reader.next(&status)
            calls += 1
        }
        return calls
    }

    func testReadsEveryChunkThenEndsCleanly() {
        var served = 0
        let reader = ChunkReader(totalFrames: 2048, buffer: buffer(), chunkFrames: 1024) { buf, wanted in
            served += 1
            buf.frameLength = wanted
        }
        XCTAssertEqual(drain(reader), 3)          // two chunks, then endOfStream
        XCTAssertEqual(served, 2)
        XCTAssertFalse(reader.failed)
        XCTAssertEqual(reader.framesProduced, 2048)
    }

    func testTrailingReadErrorIsTreatedAsEndOfStream() {
        struct PastEnd: Error {}
        var served = 0
        let reader = ChunkReader(totalFrames: 2048, buffer: buffer(), chunkFrames: 1024) { buf, wanted in
            served += 1
            if served > 1 { throw PastEnd() }     // the padding frames the container promised
            buf.frameLength = wanted
        }
        _ = drain(reader)
        XCTAssertFalse(reader.failed, "a throw after real audio is the end of the stream")
        XCTAssertEqual(reader.framesProduced, 1024)
    }

    func testImmediateReadErrorIsAFailure() {
        struct Broken: Error {}
        let reader = ChunkReader(totalFrames: 2048, buffer: buffer(), chunkFrames: 1024) { _, _ in throw Broken() }
        _ = drain(reader)
        XCTAssertTrue(reader.failed, "a file that yields no audio at all is unreadable")
        XCTAssertEqual(reader.framesProduced, 0)
    }

    func testZeroFramesEndsTheStream() {
        let reader = ChunkReader(totalFrames: 2048, buffer: buffer(), chunkFrames: 1024) { buf, _ in
            buf.frameLength = 0
        }
        var status = AVAudioConverterInputStatus.haveData
        XCTAssertNil(reader.next(&status))
        XCTAssertEqual(status, .endOfStream)
        XCTAssertFalse(reader.failed)
    }

    func testNeverRequestsMoreThanRemains() {
        var requested: [AVAudioFrameCount] = []
        let reader = ChunkReader(totalFrames: 1500, buffer: buffer(), chunkFrames: 1024) { buf, wanted in
            requested.append(wanted)
            buf.frameLength = wanted
        }
        _ = drain(reader)
        XCTAssertEqual(requested, [1024, 476])
    }
}
