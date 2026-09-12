import Foundation

public struct ContactRecord: Sendable, Equatable {
    public var jid: String
    public var displayName: String
    public var isSaved: Bool
    public var pinned: Bool
    public var blacklisted: Bool
    public var avatarPath: String?

    public init(jid: String, displayName: String, isSaved: Bool, pinned: Bool, blacklisted: Bool,
                avatarPath: String?) {
        self.jid = jid
        self.displayName = displayName
        self.isSaved = isSaved
        self.pinned = pinned
        self.blacklisted = blacklisted
        self.avatarPath = avatarPath
    }

    init(row: SQLiteRow) {
        jid = row.string("jid") ?? ""
        displayName = row.string("displayName") ?? ""
        isSaved = row.bool("isSaved") ?? false
        pinned = row.bool("pinned") ?? false
        blacklisted = row.bool("blacklisted") ?? false
        avatarPath = row.string("avatarPath")
    }
}

/// A stored verdict, flattened so the feed can render it without recomputing anything.
public struct VerdictRecord: Sendable, Equatable {
    public var messagePK: Int64
    public var senderJID: String
    public var chatJID: String
    public var chatIsGroup: Bool
    public var date: Date
    public var durationSeconds: Int
    public var relativeMediaPath: String
    public var kind: String
    public var colour: String
    public var comparedJID: String?
    public var score: Double?
    public var bestJID: String?
    public var bestScore: Double?
    public var reason: String?
    public var explanation: String
    public var speechSeconds: Double
    public var computedAt: Date
    public var modelVersion: String

    public var isRed: Bool { colour == VerdictColour.red.rawValue }

    public init(note: VoiceNoteRecord, verdict: Verdict, speechSeconds: Double, computedAt: Date,
                modelVersion: String) {
        messagePK = note.messagePK
        senderJID = note.senderJID
        chatJID = note.chatJID
        chatIsGroup = note.chatIsGroup
        date = note.date
        durationSeconds = note.durationSeconds
        relativeMediaPath = note.relativeMediaPath
        kind = verdict.kind.rawValue
        colour = verdict.colour.rawValue
        comparedJID = verdict.comparedJID
        score = verdict.score.map(Double.init)
        bestJID = verdict.best?.jid
        bestScore = verdict.best.map { Double($0.score) }
        reason = verdict.reason
        explanation = verdict.explanation
        self.speechSeconds = speechSeconds
        self.computedAt = computedAt
        self.modelVersion = modelVersion
    }

    init(row: SQLiteRow) {
        messagePK = row.int("messagePK") ?? 0
        senderJID = row.string("senderJID") ?? ""
        chatJID = row.string("chatJID") ?? ""
        chatIsGroup = row.bool("chatIsGroup") ?? false
        date = Date(timeIntervalSinceReferenceDate: row.double("date") ?? 0)
        durationSeconds = Int(row.int("durationSeconds") ?? 0)
        relativeMediaPath = row.string("relativeMediaPath") ?? ""
        kind = row.string("kind") ?? VerdictKind.unverifiable.rawValue
        colour = row.string("colour") ?? VerdictColour.grey.rawValue
        comparedJID = row.string("comparedJID")
        score = row.double("score")
        bestJID = row.string("bestJID")
        bestScore = row.double("bestScore")
        reason = row.string("reason")
        explanation = row.string("explanation") ?? ""
        speechSeconds = row.double("speechSeconds") ?? 0
        computedAt = Date(timeIntervalSinceReferenceDate: row.double("computedAt") ?? 0)
        modelVersion = row.string("modelVersion") ?? ""
    }
}
