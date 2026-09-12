import Foundation

/// How worried PhishGuard is about a message.
public enum MailTier: String, Sendable, Codable, Equatable {
    case danger, caution, safe, unknown

    public init(raw: String) {
        self = MailTier(rawValue: raw.lowercased()) ?? .unknown
    }

    /// Danger first, so a list sorted by rank reads worst-first.
    public var rank: Int {
        switch self {
        case .danger: 0
        case .caution: 1
        case .safe: 2
        case .unknown: 3
        }
    }

    public var isAlarming: Bool { self == .danger }

    public var title: String {
        switch self {
        case .danger: "Likely phishing"
        case .caution: "Worth a look"
        case .safe: "Looks fine"
        case .unknown: "Not checked"
        }
    }
}

/// One reason PhishGuard reached its verdict.
public struct MailFinding: Sendable, Codable, Equatable, Identifiable {
    public let code: String
    public let detail: String
    public let weight: Double

    public var id: String { code }

    public init(code: String, detail: String = "", weight: Double = 0) {
        self.code = code
        self.detail = detail
        self.weight = weight
    }

    /// Mitigating findings carry no weight, so both fields are optional on the wire.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case code, detail, weight }

    /// PhishGuard names its findings like constants. A person reading a verdict needs a sentence.
    public static func explain(_ code: String) -> String {
        if let known = explanations[code] { return known }
        // Anything unmapped still has to read as words rather than an identifier.
        return code.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    public var explanation: String { Self.explain(code) }

    private static let explanations: [String: String] = [
        "DMARC_FAIL": "The sender's own domain says this message should have been rejected.",
        "DMARC_FAIL_ENFORCED": "The sender's domain publishes a strict policy, and this message broke it.",
        "DMARC_MISSING": "The sender's domain publishes no policy, so nothing vouches for this message.",
        "SPF_FAIL": "The server that sent this is not one the sender's domain allows.",
        "SPF_SOFTFAIL": "The sending server is not one the sender's domain expects.",
        "DKIM_FAIL": "The message signature does not check out.",
        "DKIM_UNALIGNED": "The signature belongs to a different domain than the sender's address.",
        "AUTH_RESULTS_MISSING": "Nothing recorded whether this message was authenticated.",
        "DISPLAY_NAME_IMPERSONATION": "The name on the message does not belong to the address that sent it.",
        "LOOKALIKE_DOMAIN": "The sending domain is a near-copy of one you trust.",
        "FIRST_CONTACT": "You have never had mail from this sender before.",
        "REPLY_TO_MISMATCH": "A reply would go to a different address than the one that wrote to you.",
        "RETURN_PATH_MISMATCH": "Bounces for this message go somewhere other than the sender.",
        "URL_ANCHOR_MISMATCH": "A link shows one address and goes to another.",
        "URL_OPEN_REDIRECT": "A link bounces through a redirector that can send you anywhere.",
        "URL_BRAND_IN_SUBDOMAIN": "A link puts a familiar brand in front of an unfamiliar domain.",
        "URL_IP_LITERAL": "A link points at a bare IP address rather than a name.",
        "URL_SHORTENER": "A link is shortened, so its real destination is hidden.",
        "URL_PUNYCODE": "A link uses characters that can be made to look like other letters.",
        "HTML_HIDDEN_TEXT": "The message hides text that you cannot see but a filter can.",
        "HTML_FORM": "The message contains a form that would send what you type straight out.",
        "ATTACHMENT_EXECUTABLE": "An attachment can run code.",
        "ATTACHMENT_MACRO": "An attachment carries macros.",
        "ATTACHMENT_DOUBLE_EXTENSION": "An attachment hides its real type behind a second extension.",
        "QR_CODE_PRESENT": "An image contains a QR code, which hides where it leads.",
        "URGENCY_LANGUAGE": "The wording pushes you to act quickly.",
        "CREDENTIAL_REQUEST": "The message asks for a password or a login.",
        "PAYMENT_REQUEST": "The message asks about money or payment details.",
    ]
}

/// One message, as PhishGuard judged it.
public struct MailMessage: Sendable, Identifiable, Equatable {
    public let id: String
    public let path: String
    public let mailbox: String
    public let subject: String
    public let fromAddress: String
    public let fromDisplay: String
    public let fromDomain: String
    public let receivedAt: String
    public let snippet: String
    public let tier: MailTier
    public let score: Double
    public let headline: String
    public let findings: [MailFinding]
    public let mitigating: [MailFinding]
    public let attachmentNames: [String]
    public let hasImages: Bool

    public var date: Date? { MailDate.parse(receivedAt) }

    /// The name to show: whatever the sender called themselves, or their address.
    public var displayName: String {
        fromDisplay.isEmpty ? fromAddress : fromDisplay
    }
}

/// Mail dates arrive with and without fractional seconds. Formatters are not Sendable, so one is
/// built per call rather than shared.
enum MailDate {
    static func parse(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

/// One run of the bridge.
public struct MailScan: Sendable, Equatable {
    public let scanned: Int
    public let account: String
    public let tiers: [String: Int]
    public let messages: [MailMessage]

    public static func decode(_ data: Data) throws -> MailScan {
        let raw = try JSONDecoder().decode(RawScan.self, from: data)
        return MailScan(
            scanned: raw.scanned ?? 0,
            account: raw.account ?? "",
            tiers: raw.tiers ?? [:],
            messages: (raw.messages ?? []).map { m in
                MailMessage(id: m.localID, path: m.path, mailbox: m.mailbox,
                            subject: m.subject, fromAddress: m.fromAddress,
                            fromDisplay: m.fromDisplay, fromDomain: m.fromDomain,
                            receivedAt: m.receivedAt, snippet: m.snippet,
                            tier: MailTier(raw: m.tier), score: m.score,
                            headline: m.headline,
                            findings: m.findings ?? [], mitigating: m.mitigating ?? [],
                            attachmentNames: m.attachmentNames ?? [],
                            hasImages: m.hasImages ?? false)
            })
    }

    private struct RawScan: Decodable {
        let scanned: Int?
        let account: String?
        let tiers: [String: Int]?
        let messages: [RawMessage]?
    }

    private struct RawMessage: Decodable {
        let localID: String
        let path: String
        let mailbox: String
        let subject: String
        let fromAddress: String
        let fromDisplay: String
        let fromDomain: String
        let receivedAt: String
        let snippet: String
        let tier: String
        let score: Double
        let headline: String
        let findings: [MailFinding]?
        let mitigating: [MailFinding]?
        let attachmentNames: [String]?
        let hasImages: Bool?
    }
}
