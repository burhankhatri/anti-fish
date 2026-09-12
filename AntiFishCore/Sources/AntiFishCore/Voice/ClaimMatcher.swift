import Foundation

/// Decides whether an unsaved number is claiming to be someone the user knows.
///
/// The profile name is chosen by the sender, so it is only ever evidence of a claim. Matching it
/// against enrolled contacts is what lets a verdict say "claims to be Abdul, does not sound like
/// Abdul" instead of the far less useful "unknown voice".
public enum ClaimMatcher {
    /// Lowercase, accents removed, letters and single spaces only.
    public static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0 == " " }
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// A first name shorter than this is too common to accuse anyone over.
    private static let minFirstNameLength = 3

    public static func claimedJID(pushName: String?, enrolled: [String], names: [String: String]) -> String? {
        guard let push = pushName.map(normalize), !push.isEmpty else { return nil }
        let pushFirst = push.split(separator: " ").first.map(String.init) ?? push
        for jid in enrolled {
            guard let full = names[jid].map(normalize), !full.isEmpty else { continue }
            if full == push { return jid }
            let first = full.split(separator: " ").first.map(String.init) ?? full
            if first.count >= minFirstNameLength, first == pushFirst { return jid }
        }
        return nil
    }
}
