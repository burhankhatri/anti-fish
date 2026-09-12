import Foundation

/// Keeps an open thread current without rebuilding it.
///
/// Opening a chat checks up to thirty voice notes. Replacing the whole thread after each one meant
/// thirty full re-renders, and the scroll position was discarded every time, so the list could not
/// be scrolled while it worked.
public enum ThreadUpdate {
    /// Puts one verdict on its own row and leaves every other row exactly as it was.
    public static func applying(_ verdict: VerdictRecord,
                                to rows: [(ChatMessage, VerdictRecord?)]) -> [(ChatMessage, VerdictRecord?)] {
        rows.map { message, existing in
            message.messagePK == verdict.messagePK ? (message, verdict) : (message, existing)
        }
    }

    /// Jump to the newest message when a different chat opens. Stay where the reader put it while
    /// the chat they are already looking at is being checked.
    public static func shouldScrollToBottom(previousChat: Int64?, newChat: Int64?) -> Bool {
        guard let newChat else { return false }
        return previousChat != newChat
    }
}
