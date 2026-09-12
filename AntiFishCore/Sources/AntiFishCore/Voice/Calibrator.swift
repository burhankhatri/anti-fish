import Foundation

public struct CalibrationResult: Sendable, Equatable, Codable {
    public let thresholds: Thresholds
    public let contactCount: Int
    public let genuineCount: Int
    public let impostorCount: Int
    public let genuineMedian: Float
    public let impostorMedian: Float
    /// How often the learned threshold gets it wrong, in either direction.
    public let errorRate: Float
    public let calibratedAt: Date

    public init(thresholds: Thresholds, contactCount: Int, genuineCount: Int, impostorCount: Int,
                genuineMedian: Float, impostorMedian: Float, errorRate: Float = 0,
                calibratedAt: Date) {
        self.thresholds = thresholds
        self.contactCount = contactCount
        self.genuineCount = genuineCount
        self.impostorCount = impostorCount
        self.genuineMedian = genuineMedian
        self.impostorMedian = impostorMedian
        self.errorRate = errorRate
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
                genuine.append(VoiceMatcher.score(probe: embedding, centroid: Vector.centroid(rest),
                                                  noteEmbeddings: rest))
                for (otherJID, centroid) in centroids where otherJID != jid {
                    impostor.append(VoiceMatcher.score(probe: embedding, centroid: centroid,
                                                       noteEmbeddings: bySender[otherJID] ?? []))
                }
            }
        }

        var thresholds = defaults
        var error: Float = 0
        if bySender.count >= minContacts, !genuine.isEmpty, !impostor.isEmpty {
            let point = equalErrorThreshold(genuine: genuine, impostor: impostor)
            thresholds = Thresholds(decision: point, calibrated: true)
            error = errorRate(at: point, genuine: genuine, impostor: impostor)
        }
        return CalibrationResult(thresholds: thresholds,
                                 contactCount: bySender.count,
                                 genuineCount: genuine.count,
                                 impostorCount: impostor.count,
                                 genuineMedian: median(genuine),
                                 impostorMedian: median(impostor),
                                 errorRate: error,
                                 calibratedAt: now)
    }

    /// The score where wrongly clearing a stranger and wrongly flagging a friend happen equally
    /// often. Searching the whole range is cheap and avoids assuming either distribution's shape.
    public static func equalErrorThreshold(genuine: [Float], impostor: [Float]) -> Float {
        guard !genuine.isEmpty, !impostor.isEmpty else { return Thresholds().decision }
        var best = (gap: Float.greatestFiniteMagnitude, point: Thresholds().decision)
        for step in 0...1000 {
            let point = -1 + 2 * Float(step) / 1000
            let falseAccept = Float(impostor.count { $0 >= point }) / Float(impostor.count)
            let falseReject = Float(genuine.count { $0 < point }) / Float(genuine.count)
            let gap = abs(falseAccept - falseReject)
            if gap < best.gap { best = (gap, point) }
        }
        return best.point
    }

    /// The average of the two ways the threshold can be wrong.
    public static func errorRate(at point: Float, genuine: [Float], impostor: [Float]) -> Float {
        guard !genuine.isEmpty, !impostor.isEmpty else { return 0 }
        let falseAccept = Float(impostor.count { $0 >= point }) / Float(impostor.count)
        let falseReject = Float(genuine.count { $0 < point }) / Float(genuine.count)
        return (falseAccept + falseReject) / 2
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
