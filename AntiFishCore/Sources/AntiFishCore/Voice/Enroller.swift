import Foundation

public struct EnrollmentPolicy: Sendable, Equatable {
    /// Below these a fingerprint is too thin to judge anyone by.
    public var minNotes = 3
    public var minSpeechSeconds = 30.0
    /// A voice drifts; only recent notes describe it.
    public var maxNotes = 30
    public var protectedCount = 10

    public init() {}
}

public enum Enroller {
    /// Builds one fingerprint per sender who has enough recent voice, newest sender first.
    public static func fingerprints(from notes: [EnrolledNote], policy: EnrollmentPolicy,
                                    center: EmbeddingCenter, modelVersion: String) -> [Fingerprint] {
        Dictionary(grouping: notes.filter { !$0.embedding.isEmpty }, by: \.jid)
            .compactMap { jid, all -> Fingerprint? in
                let kept = Array(all.sorted { $0.date > $1.date }.prefix(policy.maxNotes))
                let speech = kept.reduce(0) { $0 + $1.speechSeconds }
                guard kept.count >= policy.minNotes, speech >= policy.minSpeechSeconds else { return nil }
                return Fingerprint(jid: jid,
                                   centroid: center.centroid(of: kept.map(\.embedding)),
                                   noteCount: kept.count,
                                   speechSeconds: speech,
                                   lastNoteDate: kept[0].date,
                                   modelVersion: modelVersion)
            }
            .sorted { $0.lastNoteDate > $1.lastNoteDate }
    }

    /// Pinned contacts first, then the most recently active, up to `protectedCount`.
    /// A pin for someone without a fingerprint is ignored rather than taking a slot.
    public static func protectedJIDs(_ fingerprints: [Fingerprint], pinned: [String],
                                     policy: EnrollmentPolicy) -> [String] {
        let enrolled = Set(fingerprints.map(\.jid))
        var result = pinned.filter(enrolled.contains)
        for fp in fingerprints.sorted(by: { $0.lastNoteDate > $1.lastNoteDate }) where !result.contains(fp.jid) {
            if result.count >= policy.protectedCount { break }
            result.append(fp.jid)
        }
        return result
    }

    /// Lets a newly verified note join a contact's enrolment, so a fingerprint keeps up with the
    /// voice. The gate is what stops an impostor's note from being absorbed: same sender, a score
    /// at or above the match threshold, real speech, and not already enrolled.
    /// Returns the merged list newest-first, or nil when the note is rejected.
    public static func rollingAppend(existing: [EnrolledNote], candidate: EnrolledNote, score: Float,
                                     thresholds: Thresholds, policy: EnrollmentPolicy) -> [EnrolledNote]? {
        guard !candidate.embedding.isEmpty,
              candidate.speechSeconds >= 2,
              score >= thresholds.decision,
              existing.allSatisfy({ $0.jid == candidate.jid }),
              !existing.contains(where: { $0.messagePK == candidate.messagePK }) else { return nil }
        return Array((existing + [candidate]).sorted { $0.date > $1.date }.prefix(policy.maxNotes))
    }
}
