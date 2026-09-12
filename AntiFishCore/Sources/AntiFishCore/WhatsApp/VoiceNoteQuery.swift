import Foundation

/// One voice-note row from ChatStorage.sqlite.
///
/// `senderJID` is the group member for group chats, the chat JID for 1:1 chats, and empty for notes
/// the user sent themselves.
public struct VoiceNoteRecord: Sendable, Equatable, Hashable {
    public let messagePK: Int64
    public let chatJID: String
    public let senderJID: String
    public let isFromMe: Bool
    public let date: Date
    public let durationSeconds: Int
    public let relativeMediaPath: String
    public let chatIsGroup: Bool

    public init(messagePK: Int64, chatJID: String, senderJID: String, isFromMe: Bool, date: Date,
                durationSeconds: Int, relativeMediaPath: String, chatIsGroup: Bool) {
        self.messagePK = messagePK
        self.chatJID = chatJID
        self.senderJID = senderJID
        self.isFromMe = isFromMe
        self.date = date
        self.durationSeconds = durationSeconds
        self.relativeMediaPath = relativeMediaPath
        self.chatIsGroup = chatIsGroup
    }
}

public enum VoiceNoteQuery {
    /// `ZMESSAGETYPE` 3 is a voice note; 2 is video. Only rows whose media has a local path are
    /// analysable, and `ZMESSAGEDATE` counts seconds from the Core Data epoch (2001-01-01).
    static let sql = """
        SELECT m.Z_PK AS pk, m.ZFROMJID AS fromJID, m.ZTOJID AS toJID, m.ZISFROMME AS isFromMe,
               m.ZMESSAGEDATE AS date, mi.ZMOVIEDURATION AS duration, mi.ZMEDIALOCALPATH AS path,
               gm.ZMEMBERJID AS memberJID, s.ZCONTACTJID AS sessionJID,
               (s.ZGROUPINFO IS NOT NULL) AS isGroup
        FROM ZWAMESSAGE m
        JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM
        LEFT JOIN ZWAGROUPMEMBER gm ON gm.Z_PK = m.ZGROUPMEMBER
        LEFT JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
        WHERE m.ZMESSAGETYPE = 3 AND mi.ZMEDIALOCALPATH IS NOT NULL AND m.Z_PK > :afterPK
        ORDER BY m.Z_PK ASC
        """

    public static func fetch(_ store: ChatStore, afterPK: Int64 = 0) throws -> [VoiceNoteRecord] {
        try store.db.query(sql, named: ["afterPK": .int(afterPK)]).map(record(from:))
    }

    public static func maxMessagePK(_ store: ChatStore) throws -> Int64 {
        try store.db.scalarInt("SELECT COALESCE(MAX(Z_PK), 0) FROM ZWAMESSAGE") ?? 0
    }

    /// Oldest incoming voice note newer than `since` whose media has not downloaded yet. The live
    /// cursor must not advance past it, or the note is missed once the file lands.
    public static func pendingFloor(_ store: ChatStore, since: Date) throws -> Int64? {
        let rows = try store.db.query("""
            SELECT MIN(m.Z_PK) AS floorPK FROM ZWAMESSAGE m
            JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM
            WHERE m.ZMESSAGETYPE = 3 AND m.ZISFROMME = 0 AND mi.ZMEDIALOCALPATH IS NULL
              AND m.ZMESSAGEDATE > :since
            """, named: ["since": .double(since.timeIntervalSinceReferenceDate)])
        return rows.first?.int("floorPK")
    }

    static func record(from row: SQLiteRow) -> VoiceNoteRecord {
        let isGroup = row.bool("isGroup") ?? false
        let isFromMe = row.bool("isFromMe") ?? false
        let fromJID = row.string("fromJID")
        let chatJID = row.string("sessionJID") ?? fromJID ?? row.string("toJID") ?? ""
        let sender: String
        if isFromMe {
            sender = ""
        } else if isGroup {
            sender = row.string("memberJID") ?? fromJID ?? ""
        } else {
            sender = fromJID ?? chatJID
        }
        return VoiceNoteRecord(
            messagePK: row.int("pk") ?? 0,
            chatJID: chatJID,
            senderJID: sender,
            isFromMe: isFromMe,
            date: Date(timeIntervalSinceReferenceDate: row.double("date") ?? 0),
            durationSeconds: Int(row.int("duration") ?? 0),
            relativeMediaPath: row.string("path") ?? "",
            chatIsGroup: isGroup)
    }
}
