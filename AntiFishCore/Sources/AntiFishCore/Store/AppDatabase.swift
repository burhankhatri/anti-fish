import Foundation

/// AntiFish's own store: contacts, enrolment notes, fingerprints, verdicts and settings.
/// Everything lives on this Mac; nothing here is ever sent anywhere.
public final class AppDatabase: Sendable {
    public let db: SQLiteDatabase

    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AntiFish/antifish.sqlite")
    }

    /// `nil` opens a private in-memory database, which is what tests use.
    public init(url: URL?) throws {
        db = try url.map { try SQLiteDatabase(url: $0, readOnly: false) } ?? SQLiteDatabase.inMemory()
        try db.migrate(Self.migrations)
    }

    /// Computed rather than stored: Swift 6 will not let closures live in global state.
    static var migrations: [(String, (SQLiteDatabase) throws -> Void)] { [
        ("v1", { db in
            try db.execute("""
                CREATE TABLE contact (
                    jid TEXT PRIMARY KEY, displayName TEXT NOT NULL,
                    isSaved INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0,
                    blacklisted INTEGER NOT NULL DEFAULT 0, avatarPath TEXT);

                CREATE TABLE enrollmentNote (
                    messagePK INTEGER PRIMARY KEY, jid TEXT NOT NULL, embedding BLOB NOT NULL,
                    speechSeconds REAL NOT NULL, date REAL NOT NULL);
                CREATE INDEX enrollmentNote_jid ON enrollmentNote (jid);

                CREATE TABLE fingerprint (
                    jid TEXT PRIMARY KEY, centroid BLOB NOT NULL, noteCount INTEGER NOT NULL,
                    speechSeconds REAL NOT NULL, lastNoteDate REAL NOT NULL, modelVersion TEXT NOT NULL);

                CREATE TABLE verdict (
                    messagePK INTEGER PRIMARY KEY, senderJID TEXT NOT NULL, chatJID TEXT NOT NULL,
                    chatIsGroup INTEGER NOT NULL, date REAL NOT NULL, durationSeconds INTEGER NOT NULL,
                    relativeMediaPath TEXT NOT NULL, kind TEXT NOT NULL, colour TEXT NOT NULL,
                    comparedJID TEXT, score REAL, bestJID TEXT, bestScore REAL, reason TEXT,
                    explanation TEXT NOT NULL, speechSeconds REAL NOT NULL, computedAt REAL NOT NULL,
                    modelVersion TEXT NOT NULL);
                CREATE INDEX verdict_date ON verdict (date DESC);
                CREATE INDEX verdict_sender ON verdict (senderJID);

                CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                """)
        }),
    ] }

    // MARK: Contacts

    public func saveContacts(_ contacts: [ContactRecord]) throws {
        try db.transaction {
            for c in contacts {
                try db.run("""
                    INSERT INTO contact (jid, displayName, isSaved, pinned, blacklisted, avatarPath)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(jid) DO UPDATE SET displayName = excluded.displayName,
                        isSaved = excluded.isSaved, pinned = excluded.pinned,
                        blacklisted = excluded.blacklisted, avatarPath = excluded.avatarPath
                    """, [.text(c.jid), .text(c.displayName), .int(c.isSaved ? 1 : 0),
                          .int(c.pinned ? 1 : 0), .int(c.blacklisted ? 1 : 0),
                          c.avatarPath.map { SQLiteValue.text($0) } ?? .null])
            }
        }
    }

    public func contacts() throws -> [ContactRecord] {
        try db.query("SELECT * FROM contact ORDER BY displayName").map(ContactRecord.init(row:))
    }

    public func contact(jid: String) throws -> ContactRecord? {
        try db.query("SELECT * FROM contact WHERE jid = ?", [.text(jid)]).first.map(ContactRecord.init(row:))
    }

    public func setPinned(jid: String, _ pinned: Bool) throws {
        try db.run("UPDATE contact SET pinned = ? WHERE jid = ?", [.int(pinned ? 1 : 0), .text(jid)])
    }

    public func setBlacklisted(jid: String, _ blacklisted: Bool) throws {
        try db.run("UPDATE contact SET blacklisted = ? WHERE jid = ?", [.int(blacklisted ? 1 : 0), .text(jid)])
    }

    // MARK: Enrolment

    public func replaceEnrollment(jid: String, notes: [EnrolledNote]) throws {
        try db.transaction {
            try db.run("DELETE FROM enrollmentNote WHERE jid = ?", [.text(jid)])
            for note in notes {
                try db.run("""
                    INSERT INTO enrollmentNote (messagePK, jid, embedding, speechSeconds, date)
                    VALUES (?, ?, ?, ?, ?)
                    """, [.int(note.messagePK), .text(note.jid), .blob(Vector.toData(note.embedding)),
                          .double(note.speechSeconds), .double(note.date.timeIntervalSinceReferenceDate)])
            }
        }
    }

    public func enrollmentNotes(jid: String) throws -> [EnrolledNote] {
        try db.query("SELECT * FROM enrollmentNote WHERE jid = ? ORDER BY messagePK", [.text(jid)])
            .map(Self.enrolledNote(from:))
    }

    public func allEnrollmentNotes() throws -> [EnrolledNote] {
        try db.query("SELECT * FROM enrollmentNote ORDER BY messagePK").map(Self.enrolledNote(from:))
    }

    private static func enrolledNote(from row: SQLiteRow) -> EnrolledNote {
        EnrolledNote(jid: row.string("jid") ?? "",
                     messagePK: row.int("messagePK") ?? 0,
                     embedding: row.data("embedding").map(Vector.fromData) ?? [],
                     speechSeconds: row.double("speechSeconds") ?? 0,
                     date: Date(timeIntervalSinceReferenceDate: row.double("date") ?? 0))
    }

    // MARK: Fingerprints

    public func saveFingerprints(_ fingerprints: [Fingerprint]) throws {
        try db.transaction {
            try db.run("DELETE FROM fingerprint")
            for fp in fingerprints {
                try db.run("""
                    INSERT INTO fingerprint (jid, centroid, noteCount, speechSeconds, lastNoteDate, modelVersion)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, [.text(fp.jid), .blob(Vector.toData(fp.centroid)), .int(Int64(fp.noteCount)),
                          .double(fp.speechSeconds), .double(fp.lastNoteDate.timeIntervalSinceReferenceDate),
                          .text(fp.modelVersion)])
            }
        }
    }

    public func fingerprints() throws -> [Fingerprint] {
        try db.query("SELECT * FROM fingerprint ORDER BY lastNoteDate DESC").map { row in
            Fingerprint(jid: row.string("jid") ?? "",
                        centroid: row.data("centroid").map(Vector.fromData) ?? [],
                        noteCount: Int(row.int("noteCount") ?? 0),
                        speechSeconds: row.double("speechSeconds") ?? 0,
                        lastNoteDate: Date(timeIntervalSinceReferenceDate: row.double("lastNoteDate") ?? 0),
                        modelVersion: row.string("modelVersion") ?? "")
        }
    }

    // MARK: Verdicts

    public func saveVerdict(_ v: VerdictRecord) throws {
        try db.run("""
            INSERT OR REPLACE INTO verdict
              (messagePK, senderJID, chatJID, chatIsGroup, date, durationSeconds, relativeMediaPath,
               kind, colour, comparedJID, score, bestJID, bestScore, reason, explanation,
               speechSeconds, computedAt, modelVersion)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.int(v.messagePK), .text(v.senderJID), .text(v.chatJID), .int(v.chatIsGroup ? 1 : 0),
                  .double(v.date.timeIntervalSinceReferenceDate), .int(Int64(v.durationSeconds)),
                  .text(v.relativeMediaPath), .text(v.kind), .text(v.colour),
                  v.comparedJID.map { SQLiteValue.text($0) } ?? .null,
                  v.score.map { SQLiteValue.double($0) } ?? .null,
                  v.bestJID.map { SQLiteValue.text($0) } ?? .null,
                  v.bestScore.map { SQLiteValue.double($0) } ?? .null,
                  v.reason.map { SQLiteValue.text($0) } ?? .null,
                  .text(v.explanation), .double(v.speechSeconds),
                  .double(v.computedAt.timeIntervalSinceReferenceDate), .text(v.modelVersion)])
    }

    public func verdicts(limit: Int) throws -> [VerdictRecord] {
        try db.query("SELECT * FROM verdict ORDER BY date DESC, messagePK DESC LIMIT ?",
                     [.int(Int64(limit))]).map(VerdictRecord.init(row:))
    }

    public func verdict(messagePK: Int64) throws -> VerdictRecord? {
        try db.query("SELECT * FROM verdict WHERE messagePK = ?", [.int(messagePK)])
            .first.map(VerdictRecord.init(row:))
    }

    /// Replaces a verdict's judgment while keeping the note it describes. Used when the user
    /// overrules the app, which is always allowed to win.
    public func overrideVerdict(messagePK: Int64, kind: VerdictKind, colour: VerdictColour,
                                reason: String, explanation: String) throws {
        try db.run("""
            UPDATE verdict SET kind = ?, colour = ?, reason = ?, explanation = ? WHERE messagePK = ?
            """, [.text(kind.rawValue), .text(colour.rawValue), .text(reason), .text(explanation),
                  .int(messagePK)])
    }

    // MARK: Settings

    public func setting(_ key: String) throws -> String? {
        try db.query("SELECT value FROM setting WHERE key = ?", [.text(key)]).first?.string("value")
    }

    public func setSetting(_ key: String, _ value: String) throws {
        try db.run("INSERT OR REPLACE INTO setting (key, value) VALUES (?, ?)", [.text(key), .text(value)])
    }

    public func lastSeenMessagePK() throws -> Int64 {
        Int64(try setting("lastSeenMessagePK") ?? "0") ?? 0
    }

    public func setLastSeenMessagePK(_ pk: Int64) throws {
        try setSetting("lastSeenMessagePK", String(pk))
    }

    /// Chats the user has taken out of the list. Kept here rather than in WhatsApp, which never
    /// learns about it.
    public func hiddenChatJIDs() throws -> [String] {
        guard let json = try setting("hiddenChats"),
              let list = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else { return [] }
        return list
    }

    public func setChatHidden(jid: String, _ hidden: Bool) throws {
        var list = Set(try hiddenChatJIDs())
        if hidden { list.insert(jid) } else { list.remove(jid) }
        let json = String(decoding: try JSONEncoder().encode(list.sorted()), as: UTF8.self)
        try setSetting("hiddenChats", json)
    }

    public func calibration() throws -> CalibrationResult? {
        guard let json = try setting("calibration") else { return nil }
        return try? JSONDecoder().decode(CalibrationResult.self, from: Data(json.utf8))
    }

    public func saveCalibration(_ result: CalibrationResult) throws {
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        try setSetting("calibration", json)
    }

    public func thresholds() throws -> Thresholds {
        try calibration()?.thresholds ?? Thresholds()
    }

    /// The centre is derived from every enrolled embedding, so it is stored alongside them and
    /// refreshed whenever enrolment runs.
    public func embeddingCenter() throws -> EmbeddingCenter {
        guard let json = try setting("embeddingCenter"),
              let mean = try? JSONDecoder().decode([Float].self, from: Data(json.utf8)) else {
            return .identity
        }
        return EmbeddingCenter(mean: mean)
    }

    public func saveEmbeddingCenter(_ center: EmbeddingCenter) throws {
        let json = String(decoding: try JSONEncoder().encode(center.mean), as: UTF8.self)
        try setSetting("embeddingCenter", json)
    }
}
