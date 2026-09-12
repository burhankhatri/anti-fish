import Foundation

public struct CalibrationResult: Sendable, Equatable, Codable {
    public let thresholds: Thresholds
    public let contactCount: Int
    public let genuineCount: Int
    public let impostorCount: Int
    public let genuineMedian: Float
    public let impostorMedian: Float
    public let calibratedAt: Date

    public init(thresholds: Thresholds, contactCount: Int, genuineCount: Int, impostorCount: Int,
                genuineMedian: Float, impostorMedian: Float, calibratedAt: Date) {
        self.thresholds = thresholds
        self.contactCount = contactCount
        self.genuineCount = genuineCount
        self.impostorCount = impostorCount
        self.genuineMedian = genuineMedian
        self.impostorMedian = impostorMedian
        self.calibratedAt = calibratedAt
    }
}

/// Learns where the line sits for this particular user, from their own contacts' voices.
///
/// Green means a stranger would score that high at most 1% of the time; red means one of this
/// contact's own notes would score that low at most 2% of the time. Both numbers come from the
/// user's enrolled voices, not from a lab dataset.
public enum Calibrator {
    /// Below this many contacts the distributions are too thin to learn anything.
    public static let minContacts = 5
    public static let minNotesPerContact = 3

    public static func calibrate(notes: [EnrolledNote], center: EmbeddingCenter,
                                 defaults: Thresholds = Thresholds(), now: Date = Date()) -> CalibrationResult {
        let bySender = Dictionary(grouping: notes.filter { !$0.embedding.isEmpty }, by: \.jid)
            .filter { $0.value.count >= minNotesPerContact }
            .mapValues { $0.map { center.project($0.embedding) } }
        let centroids = bySender.mapValues { Vector.centroid($0) }

        var genuine: [Float] = []
        var impostor: [Float] = []
        for (jid, own) in bySender {
            for (index, embedding) in own.enumerated() {
                var rest = own
                rest.remove(at: index)
                genuine.append(Vector.cosine(embedding, Vector.centroid(rest)))
                for (otherJID, centroid) in centroids where otherJID != jid {
                    impostor.append(Vector.cosine(embedding, centroid))
                }
            }
        }

        var thresholds = defaults
        if bySender.count >= minContacts, !genuine.isEmpty, !impostor.isEmpty {
            let imp99 = percentile(impostor, 99)
            let gen2 = percentile(genuine, 2)
            // The two can cross when a contact appears under two JIDs; keeping them ordered means
            // the overlap becomes a wide "unclear" band rather than a confident wrong answer.
            thresholds = Thresholds(reject: min(imp99, gen2), match: max(imp99, gen2), calibrated: true)
        }
        return CalibrationResult(thresholds: thresholds,
                                 contactCount: bySender.count,
                                 genuineCount: genuine.count,
                                 impostorCount: impostor.count,
                                 genuineMedian: median(genuine),
                                 impostorMedian: median(impostor),
                                 calibratedAt: now)
    }

    /// Nearest-rank percentile, `p` in 0...100. Empty input yields 0.
    public static func percentile(_ values: [Float], _ p: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((p / 100) * Double(sorted.count - 1))
        return sorted[max(0, min(sorted.count - 1, index))]
    }

    public static func median(_ values: [Float]) -> Float { percentile(values, 50) }
}
