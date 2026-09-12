import Foundation

public struct ModelPaths: Sendable, Equatable {
    public let speakerModel: String
    public let vadModel: String

    public init(speakerModel: String, vadModel: String) {
        self.speakerModel = speakerModel
        self.vadModel = vadModel
    }

    public init(directory: URL) {
        self.init(
            speakerModel: directory.appendingPathComponent("wespeaker_en_voxceleb_resnet34_LM.onnx").path,
            vadModel: directory.appendingPathComponent("silero_vad.onnx").path)
    }
}

public struct VoiceAnalysis: Sendable, Equatable {
    /// Empty when there was too little speech to fingerprint.
    public let embedding: [Float]
    public let speechSeconds: Double
    public let totalSeconds: Double

    public init(embedding: [Float], speechSeconds: Double, totalSeconds: Double) {
        self.embedding = embedding
        self.speechSeconds = speechSeconds
        self.totalSeconds = totalSeconds
    }
}

/// Owns the stateful VAD and ONNX session. Every decode, trim and embed goes through this actor,
/// so the models are used from one place and never concurrently.
public actor VoiceEngine {
    /// Below this much speech an embedding is noise, so none is produced.
    public static let minSpeechSecondsForEmbedding = 0.5

    private let trimmer: SpeechTrimmer
    private let extractor: SherpaEmbeddingExtractor
    public nonisolated let modelVersion: String

    public init(models: ModelPaths, numThreads: Int = 2) throws {
        trimmer = try SpeechTrimmer(modelPath: models.vadModel)
        extractor = try SherpaEmbeddingExtractor(modelPath: models.speakerModel, numThreads: numThreads)
        modelVersion = extractor.modelVersion
    }

    public func analyze(url: URL) throws -> VoiceAnalysis {
        try analyze(samples: try OpusDecoder.decode(url: url).samples)
    }

    public func analyze(samples: [Float]) throws -> VoiceAnalysis {
        let total = Double(samples.count) / OpusDecoder.targetSampleRate
        let trimmed = trimmer.trim(samples)
        guard trimmed.speechSeconds >= Self.minSpeechSecondsForEmbedding else {
            return VoiceAnalysis(embedding: [], speechSeconds: trimmed.speechSeconds, totalSeconds: total)
        }
        return VoiceAnalysis(embedding: try extractor.embed(trimmed.samples),
                             speechSeconds: trimmed.speechSeconds,
                             totalSeconds: total)
    }
}
