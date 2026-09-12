import Foundation

/// Refuses to call a message phishing when the only evidence is the shape of its links and the
/// sender's own domain vouches for it.
///
/// PhishGuard's weights were calibrated on a different mailbox. On this one they ranked a
/// marketing newsletter at 0.94 above a real phishing campaign at 0.82, because a tracked link and
/// a disguised link look the same from the outside. Measured over 157 spam messages:
/// `URL_BRAND_IN_SUBDOMAIN` appeared on five legitimate bulk senders and no phishing;
/// `URL_FREE_HOSTING` on three phishing messages and no legitimate ones.
///
/// Nothing here changes PhishGuard's score. This only moves a verdict down a tier, and only when
/// every risk it found is about link shape.
public enum MailRescorer {
    /// Normal for any mailing list: tracking redirects, branded sending subdomains, preheader text
    /// hidden from view, image-only layouts.
    public static let linkShapeCodes: Set<String> = [
        "URL_ANCHOR_MISMATCH", "URL_BRAND_IN_SUBDOMAIN", "URL_OPEN_REDIRECT",
        "URL_SHORTENER", "HTML_HIDDEN_TEXT", "HTML_IMAGE_ONLY", "FIRST_CONTACT",
        "REPLY_TO_OFFDOMAIN", "RETURN_PATH_OFFDOMAIN", "AUTH_RESULTS_MISSING",
    ]

    /// Evidence no amount of familiarity should excuse.
    public static let hardCodes: Set<String> = [
        "DKIM_FAIL", "DKIM_UNALIGNED", "DMARC_FAIL", "DMARC_FAIL_ENFORCED", "SPF_FAIL",
        "URL_FREE_HOSTING", "URL_IP_LITERAL", "URL_PUNYCODE", "LOOKALIKE_DOMAIN",
        "DISPLAY_NAME_IMPERSONATION", "HTML_FORM", "QR_CODE_PRESENT",
        "ATTACHMENT_EXECUTABLE", "ATTACHMENT_MACRO", "ATTACHMENT_DOUBLE_EXTENSION",
        "CREDENTIAL_REQUEST",
    ]

    public static let note = "Downgraded: the links look like marketing tracking, and this sender's own domain vouches for the message."

    /// A domain passing its own published policy, from someone already in the user's history.
    /// Either alone is weak — anyone can pass DMARC on a domain registered this morning.
    static func isVouched(_ mitigating: [MailFinding]) -> Bool {
        let codes = Set(mitigating.map(\.code))
        return codes.contains("DMARC_PASS") && codes.contains("RECURRING_SENDER")
    }

    public static func adjust(tier: MailTier, findings: [MailFinding],
                              mitigating: [MailFinding]) -> MailTier {
        guard tier == .danger else { return tier }
        // Hard evidence always wins, however familiar the sender.
        guard !findings.contains(where: { hardCodes.contains($0.code) }) else { return .danger }

        let onlyLinkShape = findings.allSatisfy { linkShapeCodes.contains($0.code) }
        guard onlyLinkShape else { return tier }

        // One tracked link on its own says nothing; two senders reached "danger" on exactly that.
        if findings.count <= 1 { return .caution }
        return isVouched(mitigating) ? .caution : tier
    }

    public static func wasAdjusted(from original: MailTier, to adjusted: MailTier) -> Bool {
        original != adjusted
    }
}
