import Foundation

/// One analysed voice note contributing to a contact's fingerprint.
/// `embedding` is stored raw; projection into the centred space happens at comparison time so the
/// centre can be recomputed without re-analysing any audio.
public struct EnrolledNote: Sendable, Equatable, Codable {
    public let jid: String
    public let messagePK: Int64
    public let embedding: [Float]
    public let speechSeconds: Double
    public let date: Date

    public init(jid: String, messagePK: Int64, embedding: [Float], speechSeconds: Double, date: Date) {
        self.jid = jid
        self.messagePK = messagePK
        self.embedding = embedding
        self.speechSeconds = speechSeconds
        self.date = date
    }
}

public struct Fingerprint: Sendable, Equatable {
    public let jid: String
    /// L2-normalised mean of the enrolled embeddings, already in the centred space.
    public let centroid: [Float]
    public let noteCount: Int
    public let speechSeconds: Double
    public let lastNoteDate: Date
    public let modelVersion: String

    public init(jid: String, centroid: [Float], noteCount: Int, speechSeconds: Double,
                lastNoteDate: Date, modelVersion: String) {
        self.jid = jid
        self.centroid = centroid
        self.noteCount = noteCount
        self.speechSeconds = speechSeconds
        self.lastNoteDate = lastNoteDate
        self.modelVersion = modelVersion
    }
}
