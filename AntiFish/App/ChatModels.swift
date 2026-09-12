import AntiFishCore
import Foundation

/// A chat as the sidebar shows it: the underlying session plus the resolved name and picture.
struct ChatRow: Identifiable, Hashable, Sendable {
    let summary: ChatSummary
    let displayName: String
    let avatarURL: URL?
    /// One line of what was last said, already turned into something readable.
    let preview: String
    /// How many voice notes in this chat AntiFish wants the user to look at.
    let attentionCount: Int

    var id: Int64 { summary.sessionPK }
    var isGroup: Bool { summary.isGroup }
    var unreadCount: Int { summary.unreadCount }
    var lastMessageDate: Date? { summary.lastMessageDate }
}

/// A message in the open thread, with whatever AntiFish has concluded about it.
struct ThreadItem: Identifiable, Hashable, Sendable {
    let message: ChatMessage
    let senderName: String
    let verdict: VerdictRecord?

    var id: Int64 { message.messagePK }
    var isFromMe: Bool { message.isFromMe }

    static func == (a: ThreadItem, b: ThreadItem) -> Bool {
        a.message == b.message && a.senderName == b.senderName && a.verdict == b.verdict
    }

    func hash(into hasher: inout Hasher) { hasher.combine(message.messagePK) }
    var isVoiceNote: Bool { message.kind == .voiceNote }

    var verdictKind: VerdictKind? {
        verdict.flatMap { VerdictKind(rawValue: $0.kind) }
    }

    var verdictColour: VerdictColour? {
        verdict.flatMap { VerdictColour(rawValue: $0.colour) }
    }

    var needsAttention: Bool { verdictColour == .red }
}
