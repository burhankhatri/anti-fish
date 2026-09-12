import Foundation
import SherpaOnnx

public protocol EmbeddingExtractor: AnyObject {
    var dimension: Int { get }
    var modelVersion: String { get }
    /// `samples` are 16 kHz mono speech that has already been trimmed by the VAD.
    /// Returns an L2-normalised vector, so cosine similarity is a plain dot product.
    func embed(_ samples: [Float]) throws -> [Float]
}

/// WeSpeaker ResNet34-LM (VoxCeleb) through sherpa-onnx, running entirely on this machine.
/// Not `Sendable`: the ONNX session is owned by `VoiceEngine`.
public final class SherpaEmbeddingExtractor: EmbeddingExtractor {
    public static let sampleRate = 16_000

    private let extractor: SherpaOnnxSpeakerEmbeddingExtractorWrapper
    public let modelVersion: String

    public init(modelPath: String, numThreads: Int = 2) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw VoiceEngineError.modelMissing(modelPath)
        }
        var config = sherpaOnnxSpeakerEmbeddingExtractorConfig(model: modelPath, numThreads: numThreads)
        extractor = SherpaOnnxSpeakerEmbeddingExtractorWrapper(config: &config)
        modelVersion = URL(fileURLWithPath: modelPath).deletingPathExtension().lastPathComponent
    }

    public var dimension: Int { extractor.dim }

    public func embed(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty else { throw VoiceEngineError.embeddingFailed }
        let stream = extractor.createStream()
        stream.acceptWaveform(samples: samples, sampleRate: Self.sampleRate)
        stream.inputFinished()
        let raw = extractor.compute(stream: stream)
        guard raw.count == dimension, raw.contains(where: { $0 != 0 }) else {
            throw VoiceEngineError.embeddingFailed
        }
        return Vector.normalized(raw)
    }
}
