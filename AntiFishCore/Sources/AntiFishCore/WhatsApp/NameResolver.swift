import Foundation

public struct ResolvedIdentity: Sendable, Equatable {
    public let jid: String
    public let displayName: String
    /// True only when the JID is in the user's synced address book (ContactsV2.sqlite).
    /// Never true for a name the sender chose for themselves.
    public let isSavedContact: Bool
    /// Chosen by the sender. An impersonator controls this string, so it is evidence of a claim,
    /// never evidence of identity.
    public let pushName: String?
    public let avatarPath: String?

    public init(jid: String, displayName: String, isSavedContact: Bool, pushName: String?, avatarPath: String?) {
        self.jid = jid
        self.displayName = displayName
        self.isSavedContact = isSavedContact
        self.pushName = pushName
        self.avatarPath = avatarPath
    }
}

/// Name lookups loaded once per pass from ContactsV2.sqlite and ChatStorage.sqlite.
public struct NameTables: Sendable, Equatable {
    /// "<digits>@lid" or "<digits>@s.whatsapp.net" -> full name from the user's address book.
    public var addressBook: [String: String] = [:]
    /// Chat JID -> the name the user saved the chat under.
    public var partnerNames: [String: String] = [:]
    /// JID -> the name the sender publishes for themselves.
    public var pushNames: [String: String] = [:]
    /// JID -> profile picture path, relative to `<container>/Message`.
    public var avatarPaths: [String: String] = [:]

    public init() {}

    public static func load(chat: ChatStore, contacts: ChatStore?) throws -> NameTables {
        var t = NameTables()

        for row in try chat.db.query("""
            SELECT ZCONTACTJID, ZCONTACTIDENTIFIER, ZPARTNERNAME FROM ZWACHATSESSION
            WHERE ZPARTNERNAME IS NOT NULL AND ZPARTNERNAME != ''
            """) {
            guard let name = row.string("ZPARTNERNAME") else { continue }
            if let jid = row.string("ZCONTACTJID") { t.partnerNames[jid] = name }
            if let alias = row.string("ZCONTACTIDENTIFIER") { t.partnerNames[alias] = name }
        }

        // Optional tables: WhatsApp ships them only on some schema versions.
        if try chat.tableExists("ZWAPROFILEPUSHNAME") {
            for row in try chat.db.query("""
                SELECT ZJID, ZPUSHNAME FROM ZWAPROFILEPUSHNAME
                WHERE ZJID IS NOT NULL AND ZPUSHNAME IS NOT NULL AND ZPUSHNAME != ''
                """) {
                if let jid = row.string("ZJID"), let name = row.string("ZPUSHNAME") { t.pushNames[jid] = name }
            }
        }
        if try chat.tableExists("ZWAPROFILEPICTUREITEM") {
            for row in try chat.db.query("""
                SELECT ZJID, ZPATH FROM ZWAPROFILEPICTUREITEM
                WHERE ZJID IS NOT NULL AND ZPATH IS NOT NULL
                """) {
                // Most rows hold an encoded blob rather than a path; only a path is useful.
                if let jid = row.string("ZJID"), let path = row.string("ZPATH"),
                   path.hasPrefix("Media/") {
                    t.avatarPaths[jid] = path
                }
            }
        }

        if let contacts, try contacts.tableExists("ZWAADDRESSBOOKCONTACT") {
            for row in try contacts.db.query("""
                SELECT ZLID, ZPHONENUMBER, ZFULLNAME FROM ZWAADDRESSBOOKCONTACT
                WHERE ZFULLNAME IS NOT NULL AND ZFULLNAME != ''
                """) {
                guard let name = row.string("ZFULLNAME") else { continue }
                if let lid = row.string("ZLID"), !lid.isEmpty { t.addressBook[lid] = name }
                if let phone = row.string("ZPHONENUMBER") {
                    let digits = phone.filter(\.isNumber)
                    if !digits.isEmpty { t.addressBook["\(digits)@s.whatsapp.net"] = name }
                }
            }
        }
        return t
    }
}

public enum NameResolver {
    /// Precedence: address book -> saved chat name (unless it is just a phone number) -> push name
    /// -> masked digits. Only an address-book hit sets `isSavedContact`.
    public static func resolve(_ jid: String, tables: NameTables) -> ResolvedIdentity {
        let saved = tables.addressBook[jid]
        let partner = tables.partnerNames[jid].flatMap { isPhoneShaped($0) ? nil : $0 }
        let push = tables.pushNames[jid]
        return ResolvedIdentity(
            jid: jid,
            displayName: saved ?? partner ?? push ?? fallbackName(for: jid),
            isSavedContact: saved != nil,
            pushName: push,
            avatarPath: tables.avatarPaths[jid])
    }

    public static func fallbackName(for jid: String) -> String {
        let digits = jid.prefix { $0 != "@" }.filter(\.isNumber)
        let last4 = String(digits.suffix(4))
        return last4.isEmpty ? "WhatsApp user" : "WA ····\(last4)"
    }

    /// True when the string is only digits and phone punctuation, so it names nobody.
    public static func isPhoneShaped(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(where: \.isNumber) else { return false }
        let allowed = CharacterSet(charactersIn: "+-() ").union(.decimalDigits)
        return trimmed.unicodeScalars.allSatisfy(allowed.contains)
    }
}
