import Foundation

/// The kinds of thing a scam message says.
public enum ScamSignal: String, Sendable, CaseIterable, Codable {
    case paymentClaim, credentialRequest, urgency, prizeBait, advanceFee, newNumberClaim, accountThreat

    /// What to tell the reader. One sentence, no jargon, because the people most often caught by
    /// these messages are the ones least able to read a technical explanation.
    public var plainWords: String {
        switch self {
        case .paymentClaim: "It claims money has been sent."
        case .credentialRequest: "It asks for a code, PIN or ID document."
        case .urgency: "It pushes you to act immediately."
        case .prizeBait: "It says you have won something."
        case .advanceFee: "It asks you to pay before you receive anything."
        case .newNumberClaim: "It says this is someone's new number."
        case .accountThreat: "It warns that an account will be blocked."
        }
    }
}

public struct ScamAssessment: Sendable, Equatable {
    public let signals: [ScamSignal]
    /// 0 to 1. Two signals from a stranger is what a real scam looks like.
    public let score: Double
    public let summary: String

    /// Worth showing the reader. Below this the message is ordinary.
    public var isWorrying: Bool { score >= 0.5 }
}

/// Finds the shapes a scam takes in plain text.
///
/// This is deliberately not a model. It runs on this Mac in microseconds, needs no service and no
/// quota, and keeps working when the image check has hit its daily cap. It catches what pixel
/// analysis cannot: a doctored payment screenshot reads as an ordinary photo, but the words inside
/// it say "Rs. 25,000 received".
public enum ScamText {
    /// Roman Urdu appears alongside English in the messages this is built for, so both are matched.
    private static let patterns: [(ScamSignal, [String])] = [
        // An amount on its own is just conversation ("lunch was 500 rupees"). A payment *claim*
        // needs the money and an assertion that it moved.
        (.paymentClaim, [
            #"\b(rs\.?|pkr|rupees)\s?[\d,]{3,}[^.]{0,40}\b(transferr?ed|sent|deposit|paid|bhej|received)"#,
            #"\b(transferr?ed|sent|deposited|paid)\b[^.]{0,40}\b(rs\.?|pkr|rupees)\s?[\d,]{3,}"#,
            #"\b(transferr?ed|deposited)\b[^.]{0,30}\b(account|payment|amount|money)\b"#,
            #"\bpais[ae]\s+(bhej|send|transfer)"#,
            #"\btransfer\s+(ho\s+gaya|kar\s+diya|done)\b"#,
            #"\b(payment|amount)\s+(sent|done|received|transferred)\b"#,
        ]),
        (.credentialRequest, [
            #"\b(otp|one[\s-]?time\s?(code|password))\b"#,
            #"\b(send|share|forward|tell|give)\b[^.]{0,25}\b(code|pin|password|otp)\b"#,
            #"\bwhat\s+is\s+your\s+(pin|password|code)\b"#,
            #"\bverification\s+code\b"#,
            #"\bcnic\b"#,
            #"\b(id|identity)\s?(card|document)\s+(photo|picture|copy|scan)\b"#,
        ]),
        (.urgency, [
            #"\b(urgent|urgently|immediately|right\s+now|asap)\b"#,
            #"\b(expires?|ending|ends)\s+(today|tonight|soon|in\s+\d)"#,
            #"\b(last|final)\s+(chance|call|warning|reminder)\b"#,
            #"\bonly\s+\d+\s+(hours?|minutes?|days?)\s+(left|remaining)\b"#,
            #"\bact\s+now\b"#,
        ]),
        (.prizeBait, [
            #"\b(you|aap)\s+(have\s+)?won\b"#,
            #"\b(lucky\s+draw|lottery|prize|jackpot)\b"#,
            #"\bcongratulations\b[^.]{0,40}\b(won|winner|selected|prize)\b"#,
        ]),
        (.advanceFee, [
            #"\b(processing|registration|clearance|release|delivery)\s+fee\b"#,
            #"\bpay\b[^.]{0,30}\b(to\s+(release|claim|receive|unlock))\b"#,
            #"\b(small|nominal|token)\s+(fee|amount|charge)\b"#,
        ]),
        (.newNumberClaim, [
            #"\b(this\s+is\s+)?my\s+new\s+(number|whatsapp|contact)\b"#,
            #"\bsave\s+(this|my)\s+(new\s+)?number\b"#,
            #"\bnaya\s+number\b"#,
        ]),
        (.accountThreat, [
            #"\baccount\b[^.]{0,25}\b(blocked|suspended|locked|closed|deactivat)"#,
            #"\b(verify|confirm)\s+your\s+account\b"#,
            #"\bunusual\s+(activity|login)\b"#,
        ]),
    ]

    public static func signals(in text: String) -> [ScamSignal] {
        let haystack = text.lowercased()
        guard !haystack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return patterns.compactMap { signal, expressions in
            expressions.contains { haystack.range(of: $0, options: .regularExpression) != nil }
                ? signal : nil
        }
    }

    /// The same words mean different things from a sister and from a number never seen before,
    /// so who is speaking is part of the judgment.
    public static func assess(_ text: String, senderIsKnown: Bool) -> ScamAssessment {
        let found = signals(in: text)
        guard !found.isEmpty else { return ScamAssessment(signals: [], score: 0, summary: "") }

        // One signal is common in ordinary messages; several together is the shape of a scam.
        var score = min(1.0, 0.3 + 0.25 * Double(found.count - 1))
        if !senderIsKnown { score = min(1.0, score + 0.3) }

        return ScamAssessment(signals: found, score: score,
                              summary: found.map(\.plainWords).joined(separator: " "))
    }
}
