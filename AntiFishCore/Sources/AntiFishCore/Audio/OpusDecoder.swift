import AVFoundation
import Foundation

public enum AudioDecodeError: Error, Equatable {
    case unreadable(String)
    case unsupportedFormat(String)
    case conversionFailed(String)
}

public struct DecodedAudio: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double

    public var seconds: Double { Double(samples.count) / sampleRate }

    public var rms: Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }
}

/// Decodes anything AVFoundation can read — WhatsApp's Ogg-Opus voice notes included — down to
/// 16 kHz mono Float32, the input the speaker model expects.
public enum OpusDecoder {
    public static let targetSampleRate: Double = 16_000

    public static func decode(url: URL) throws -> DecodedAudio {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioDecodeError.unreadable(url.lastPathComponent)
        }

        let source = file.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else {
            throw AudioDecodeError.unsupportedFormat(source.description)
        }

        // Pull input in chunks so a long note never needs one giant buffer. AVAudioFile.read
        // throws rather than returning zero frames once the file is exhausted, so the remaining
        // frame count drives the loop and the converter is told endOfStream explicitly.
        let chunkFrames: AVAudioFrameCount = 65_536
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: chunkFrames),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: chunkFrames) else {
            throw AudioDecodeError.unsupportedFormat(source.description)
        }

        let reader = ChunkReader(file: file, buffer: input, chunkFrames: chunkFrames)
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * targetSampleRate / source.sampleRate) + 1024)

        while true {
            output.frameLength = 0
            var convError: NSError?
            let status = converter.convert(to: output, error: &convError) { _, outStatus in
                reader.next(outStatus)
            }
            if reader.failed { throw AudioDecodeError.unreadable(url.lastPathComponent) }
            if let convError { throw AudioDecodeError.conversionFailed(convError.localizedDescription) }
            if status == .error { throw AudioDecodeError.conversionFailed("converter returned .error") }
            if let channel = output.floatChannelData, output.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
            }
            if status == .endOfStream || status == .inputRanDry { break }
        }

        return DecodedAudio(samples: samples, sampleRate: targetSampleRate)
    }
}

/// Feeds an `AVAudioConverter` one chunk at a time from a source that may over-declare its length.
///
/// Reference type because the converter's input block mutates this state on every call. Compressed
/// containers report an estimated frame count: real WhatsApp Ogg-Opus notes declare about 960 frames
/// (20 ms of codec padding) more than `AVAudioFile` will actually hand over, and the read for those
/// last frames throws. Once real audio has been produced, that throw is the end of the stream. A
/// source that produces nothing at all is genuinely unreadable.
final class ChunkReader {
    typealias ReadChunk = (AVAudioPCMBuffer, AVAudioFrameCount) throws -> Void

    private let buffer: AVAudioPCMBuffer
    private let chunkFrames: AVAudioFrameCount
    private let read: ReadChunk
    private var remaining: Int64
    private(set) var framesProduced: Int64 = 0
    private(set) var failed = false
    private var ended = false

    init(totalFrames: Int64, buffer: AVAudioPCMBuffer, chunkFrames: AVAudioFrameCount,
         read: @escaping ReadChunk) {
        self.remaining = totalFrames
        self.buffer = buffer
        self.chunkFrames = chunkFrames
        self.read = read
    }

    convenience init(file: AVAudioFile, buffer: AVAudioPCMBuffer, chunkFrames: AVAudioFrameCount) {
        self.init(totalFrames: file.length, buffer: buffer, chunkFrames: chunkFrames) { buf, wanted in
            try file.read(into: buf, frameCount: wanted)
        }
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        guard !ended, !failed, remaining > 0 else {
            status.pointee = .endOfStream
            return nil
        }
        let wanted = AVAudioFrameCount(min(Int64(chunkFrames), remaining))
        buffer.frameLength = 0
        do {
            try read(buffer, wanted)
        } catch {
            ended = true
            failed = framesProduced == 0
            status.pointee = .endOfStream
            return nil
        }
        guard buffer.frameLength > 0 else {
            ended = true
            status.pointee = .endOfStream
            return nil
        }
        remaining -= Int64(buffer.frameLength)
        framesProduced += Int64(buffer.frameLength)
        status.pointee = .haveData
        return buffer
    }
}
