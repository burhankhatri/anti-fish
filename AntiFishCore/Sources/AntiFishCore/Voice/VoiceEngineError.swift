public enum VoiceEngineError: Error, Equatable {
    case modelMissing(String)
    case embeddingFailed
}
