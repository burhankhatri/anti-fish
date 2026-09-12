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

    public var id: Int64 { sessionPK }

    public init(sessionPK: Int64, jid: String, savedName: String?, isGroup: Bool, isArchived: Bool,
                unreadCount: Int, lastMessageDate: Date?) {
        self.sessionPK = sessionPK
        self.jid = jid
        self.savedName = savedName
        self.isGroup = isGroup
        self.isArchived = isArchived
        self.unreadCount = unreadCount
        self.lastMessageDate = lastMessageDate
    }
}

public enum ChatListQuery {
    /// Every visible chat, most recently active first. Archived chats are marked, not hidden:
    /// an impersonator often lands in a chat the user has tucked away.
    public static func fetch(_ store: ChatStore, limit: Int = 500) throws -> [ChatSummary] {
        try store.db.query("""
            SELECT Z_PK AS pk, ZCONTACTJID AS jid, ZPARTNERNAME AS name,
                   (ZGROUPINFO IS NOT NULL) AS isGroup, ZARCHIVED AS archived,
                   ZUNREADCOUNT AS unread, ZLASTMESSAGEDATE AS lastDate
            FROM ZWACHATSESSION
            WHERE ZCONTACTJID IS NOT NULL AND COALESCE(ZHIDDEN, 0) = 0
            ORDER BY COALESCE(ZLASTMESSAGEDATE, 0) DESC
            LIMIT :limit
            """, named: ["limit": .int(Int64(limit))]).map { row in
            ChatSummary(sessionPK: row.int("pk") ?? 0,
                        jid: row.string("jid") ?? "",
                        savedName: row.string("name"),
                        isGroup: row.bool("isGroup") ?? false,
                        isArchived: row.bool("archived") ?? false,
                        unreadCount: Int(row.int("unread") ?? 0),
                        lastMessageDate: row.double("lastDate").map(Date.init(timeIntervalSinceReferenceDate:)))
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
