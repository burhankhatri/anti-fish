import Foundation
import SherpaOnnx

public struct TrimmedSpeech: Sendable, Equatable {
    public let samples: [Float]
    public let speechSeconds: Double
}

/// Silero voice-activity detection through sherpa-onnx.
///
/// Keeps only the spoken parts of a note, so silence, music and room tone never reach the speaker
/// model. Not `Sendable`: the underlying detector is stateful and is owned by `VoiceEngine`.
public final class SpeechTrimmer {
    public static let sampleRate = 16_000
    /// Silero expects exactly this window; anything else makes it reject the input.
    private static let window = 512

    private let vad: SherpaOnnxVoiceActivityDetectorWrapper

    public init(modelPath: String, bufferSeconds: Float = 120) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw VoiceEngineError.modelMissing(modelPath)
        }
        var config = sherpaOnnxVadModelConfig(
            sileroVad: sherpaOnnxSileroVadModelConfig(
                model: modelPath,
                threshold: 0.5,
                minSilenceDuration: 0.25,
                minSpeechDuration: 0.25,
                windowSize: Self.window,
                maxSpeechDuration: 20),
            sampleRate: Int32(Self.sampleRate),
            numThreads: 1)
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &config, buffer_size_in_seconds: bufferSeconds)
    }

    /// Returns the speech portions, concatenated, still at 16 kHz.
    public func trim(_ samples: [Float]) -> TrimmedSpeech {
        vad.reset()
        var kept: [Float] = []
        var index = 0
        while index < samples.count {
            let end = min(index + Self.window, samples.count)
            vad.acceptWaveform(samples: Array(samples[index..<end]))
            drain(into: &kept)
            index = end
        }
        vad.flush()
        drain(into: &kept)
        return TrimmedSpeech(samples: kept, speechSeconds: Double(kept.count) / Double(Self.sampleRate))
    }

    private func drain(into kept: inout [Float]) {
        while !vad.isEmpty() {
            kept.append(contentsOf: vad.front().samples)
            vad.pop()
        }
    }
}
