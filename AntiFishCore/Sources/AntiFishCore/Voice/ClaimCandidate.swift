import Foundation

/// Someone the user can point at and say "this caller claims to be them".
///
/// A profile name is chosen by whoever set it, so it is only ever a hint. When the user names the
/// person themselves, the app is testing a claim a human made, which is the stronger question.
public struct ClaimCandidate: Sendable, Identifiable, Equatable, Hashable {
    public let jid: String
    public let name: String
    public let noteCount: Int
    public let lastHeard: Date

    public var id: String { jid }

    public init(jid: String, name: String, noteCount: Int, lastHeard: Date) {
        self.jid = jid
        self.name = name
        self.noteCount = noteCount
        self.lastHeard = lastHeard
    }

    /// Everyone the app has a voice for, most recently heard first.
    public static func list(from fingerprints: [Fingerprint], names: [String: String]) -> [ClaimCandidate] {
        fingerprints
            .sorted { $0.lastNoteDate > $1.lastNoteDate }
            .map { fp in
                ClaimCandidate(jid: fp.jid,
                               name: names[fp.jid] ?? NameResolver.fallbackName(for: fp.jid),
                               noteCount: fp.noteCount,
                               lastHeard: fp.lastNoteDate)
            }
    }
}
