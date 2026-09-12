import AntiFishCore
import Foundation

/// One row in the feed: a stored verdict plus the names and picture needed to draw it.
struct FeedItem: Identifiable, Hashable, Sendable {
    let record: VerdictRecord
    let senderName: String
    let chatName: String?
    let avatarURL: URL?

    var id: Int64 { record.messagePK }
    var colour: VerdictColour { VerdictColour(rawValue: record.colour) ?? .grey }
    var kind: VerdictKind { VerdictKind(rawValue: record.kind) ?? .unverifiable }
    var day: Date { Calendar.current.startOfDay(for: record.date) }

    /// Worth interrupting someone over.
    var needsAttention: Bool { colour == .red }

    /// Most rows say nothing: absence is the ordinary state, so a feed of twenty rows stays still.
    /// Only a verdict that tells the reader something new earns a pill.
    static func showsPill(for kind: VerdictKind) -> Bool {
        switch kind {
        case .verified, .takeoverSuspected, .impersonationSuspected, .matchesUnsavedNumber: true
        case .unknownVoice, .unverifiable, .unclear: false
        }
    }

    var showsPill: Bool { Self.showsPill(for: kind) }
}

struct ContactRow: Identifiable, Hashable, Sendable {
    enum Tier: Int, Sendable, Comparable {
        case protected = 0, enrolled = 1, needsVoice = 2
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .protected: "Protected"
            case .enrolled: "Enrolled"
            case .needsVoice: "Needs more voice"
            }
        }
    }

    let jid: String
    let name: String
    let isSaved: Bool
    let pinned: Bool
    let noteCount: Int
    let speechSeconds: Double
    let lastNoteDate: Date?
    let tier: Tier
    let avatarURL: URL?

    var id: String { jid }
}

enum AppPhase: Equatable, Sendable {
    case starting
    case needsWhatsApp
    case needsFullDiskAccess
    case setupChoices
    case enrolling(done: Int, total: Int)
    case ready
}
