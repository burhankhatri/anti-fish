import Foundation

/// One row in the chat list.
public struct ChatSummary: Sendable, Equatable, Identifiable, Hashable {
    public let sessionPK: Int64
    public let jid: String
    /// The name the user saved this chat under, or the group's name.
    public let savedName: String?
    public let isGroup: Bool
    public let isArchived: Bool
    public let unreadCount: Int
    public let lastMessageDate: Date?
    /// Voice notes from other people whose audio is on this Mac. This is the app's evidence:
    /// a note WhatsApp never downloaded cannot be listened to, so it cannot be checked.
    public let voiceNoteCount: Int
    /// Every incoming voice note the database knows about, downloaded or not. Usually far larger:
    /// WhatsApp Desktop only fetches media from the day it was linked.
    public let voiceNoteTotal: Int

    public var id: Int64 { sessionPK }

    public init(sessionPK: Int64, jid: String, savedName: String?, isGroup: Bool, isArchived: Bool,
                unreadCount: Int, lastMessageDate: Date?, voiceNoteCount: Int = 0,
                voiceNoteTotal: Int = 0) {
        self.sessionPK = sessionPK
        self.jid = jid
        self.savedName = savedName
        self.isGroup = isGroup
        self.isArchived = isArchived
        self.unreadCount = unreadCount
        self.lastMessageDate = lastMessageDate
        self.voiceNoteCount = voiceNoteCount
        self.voiceNoteTotal = voiceNoteTotal
    }

    /// True when the database lists voice notes here but none of them can be played.
    public var hasNoPlayableAudio: Bool { voiceNoteCount == 0 && voiceNoteTotal > 0 }
}

/// How the chat list is ordered.
public enum ChatOrder: String, Sendable, CaseIterable, Identifiable {
    /// What WhatsApp does.
    case recent
    /// Chats with the most incoming voice notes first, so there is something to look at.
    case mostVoice

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recent: "Recent"
        case .mostVoice: "Most voice notes"
        }
    }

    public func apply(to chats: [ChatSummary]) -> [ChatSummary] {
        switch self {
        case .recent:
            return chats.sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
        case .mostVoice:
            return chats.sorted { a, b in
                if a.voiceNoteCount != b.voiceNoteCount { return a.voiceNoteCount > b.voiceNoteCount }
                return (a.lastMessageDate ?? .distantPast) > (b.lastMessageDate ?? .distantPast)
            }
        }
    }
}

public enum ChatListQuery {
    /// Every visible chat, most recently active first. Archived chats are marked, not hidden:
    /// an impersonator often lands in a chat the user has tucked away.
    public static func fetch(_ store: ChatStore, limit: Int = 500) throws -> [ChatSummary] {
        try store.db.query("""
            SELECT s.Z_PK AS pk, s.ZCONTACTJID AS jid, s.ZPARTNERNAME AS name,
                   (s.ZGROUPINFO IS NOT NULL) AS isGroup, s.ZARCHIVED AS archived,
                   s.ZUNREADCOUNT AS unread, s.ZLASTMESSAGEDATE AS lastDate,
                   (SELECT COUNT(*) FROM ZWAMESSAGE m
                      JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM
                      WHERE m.ZCHATSESSION = s.Z_PK AND m.ZMESSAGETYPE = 3 AND m.ZISFROMME = 0
                        AND mi.ZMEDIALOCALPATH IS NOT NULL) AS playableNotes,
                   (SELECT COUNT(*) FROM ZWAMESSAGE m
                     WHERE m.ZCHATSESSION = s.Z_PK AND m.ZMESSAGETYPE = 3 AND m.ZISFROMME = 0) AS totalNotes
            FROM ZWACHATSESSION s
            WHERE s.ZCONTACTJID IS NOT NULL AND COALESCE(s.ZHIDDEN, 0) = 0
            ORDER BY COALESCE(s.ZLASTMESSAGEDATE, 0) DESC
            LIMIT :limit
            """, named: ["limit": .int(Int64(limit))]).map { row in
            ChatSummary(sessionPK: row.int("pk") ?? 0,
                        jid: row.string("jid") ?? "",
                        savedName: row.string("name"),
                        isGroup: row.bool("isGroup") ?? false,
                        isArchived: row.bool("archived") ?? false,
                        unreadCount: Int(row.int("unread") ?? 0),
                        lastMessageDate: row.double("lastDate").map(Date.init(timeIntervalSinceReferenceDate:)),
                        voiceNoteCount: Int(row.int("playableNotes") ?? 0),
                        voiceNoteTotal: Int(row.int("totalNotes") ?? 0))
        }
    }
}

/// What a message is, mapped from WhatsApp's `ZMESSAGETYPE`.
public enum MessageKind: String, Sendable, Equatable {
    case text, image, video, voiceNote, sticker, gif, link, document, systemEvent, deleted, other

    public init(messageType: Int64) {
        switch messageType {
        case 0: self = .text
        case 1: self = .image
        case 2: self = .video
        case 3: self = .voiceNote
        case 6: self = .systemEvent
        case 7: self = .link
        case 8: self = .document
        case 11: self = .gif
        case 14: self = .deleted
        case 15: self = .sticker
        default: self = .other
        }
    }

    /// What to show when there is nothing to render but the fact that something was sent.
    public var placeholder: String {
        switch self {
        case .text, .link: ""
        case .image: "Photo"
        case .video: "Video"
        case .voiceNote: "Voice note"
        case .sticker: "Sticker"
        case .gif: "GIF"
        case .document: "Document"
        case .systemEvent: ""
        case .deleted: "This message was deleted"
        case .other: "Message"
        }
    }
}

/// One message in a thread, whatever its type.
public struct ChatMessage: Sendable, Equatable, Identifiable, Hashable {
    public let messagePK: Int64
    public let kind: MessageKind
    public let text: String?
    public let isFromMe: Bool
    /// Empty for messages the user sent.
    public let senderJID: String
    public let date: Date
    public let durationSeconds: Int
    /// Nil when the media has not been downloaded to this Mac.
    public let relativeMediaPath: String?

    public var id: Int64 { messagePK }

    /// Whether this row is worth drawing. A text message with no text is an edit or a tombstone;
    /// drawing it leaves an empty bubble and a hole in the conversation.
    public var hasSomethingToShow: Bool {
        switch kind {
        case .text, .link, .systemEvent, .other:
            return !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    /// A waveform needs consistent room whatever the note says. Text should hug its content.
    public var needsFixedWidth: Bool { kind == .voiceNote }

    public init(messagePK: Int64, kind: MessageKind, text: String?, isFromMe: Bool, senderJID: String,
                date: Date, durationSeconds: Int, relativeMediaPath: String?) {
        self.messagePK = messagePK
        self.kind = kind
        self.text = text
        self.isFromMe = isFromMe
        self.senderJID = senderJID
        self.date = date
        self.durationSeconds = durationSeconds
        self.relativeMediaPath = relativeMediaPath
    }
}

public enum MessageQuery {
    /// The messages in one chat, oldest first. `limit` keeps the most recent ones, which is what a
    /// thread view opens on.
    public static func fetch(_ store: ChatStore, sessionPK: Int64, limit: Int = 300) throws -> [ChatMessage] {
        let rows = try store.db.query("""
            SELECT m.Z_PK AS pk, m.ZMESSAGETYPE AS type, m.ZTEXT AS text, m.ZISFROMME AS isFromMe,
                   m.ZFROMJID AS fromJID, m.ZMESSAGEDATE AS date,
                   mi.ZMOVIEDURATION AS duration, mi.ZMEDIALOCALPATH AS path,
                   gm.ZMEMBERJID AS memberJID, (s.ZGROUPINFO IS NOT NULL) AS isGroup,
                   s.ZCONTACTJID AS sessionJID
            FROM ZWAMESSAGE m
            LEFT JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM
            LEFT JOIN ZWAGROUPMEMBER gm ON gm.Z_PK = m.ZGROUPMEMBER
            LEFT JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
            WHERE m.ZCHATSESSION = :session
            ORDER BY m.Z_PK DESC
            LIMIT :limit
            """, named: ["session": .int(sessionPK), "limit": .int(Int64(limit))])

        return rows.reversed().map { row in
            let isGroup = row.bool("isGroup") ?? false
            let isFromMe = row.bool("isFromMe") ?? false
            let fromJID = row.string("fromJID")
            let sender: String
            if isFromMe {
                sender = ""
            } else if isGroup {
                sender = row.string("memberJID") ?? fromJID ?? ""
            } else {
                sender = fromJID ?? row.string("sessionJID") ?? ""
            }
            let text = row.string("text")
            return ChatMessage(messagePK: row.int("pk") ?? 0,
                               kind: MessageKind(messageType: row.int("type") ?? -1),
                               text: (text?.isEmpty ?? true) ? nil : text,
                               isFromMe: isFromMe,
                               senderJID: sender,
                               date: Date(timeIntervalSinceReferenceDate: row.double("date") ?? 0),
                               durationSeconds: Int(row.int("duration") ?? 0),
                               relativeMediaPath: row.string("path"))
        }
    }
}
