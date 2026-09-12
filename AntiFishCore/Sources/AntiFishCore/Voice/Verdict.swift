import Foundation

public enum SenderClass: String, Sendable, Codable {
    /// A number in the user's address book that has a voice fingerprint.
    case knownEnrolled
    /// A number in the address book with too little voice to judge.
    case knownUnenrolled
    /// Any number the user has not saved, including group members.
    case unknown
}

public struct Comparison: Sendable, Equatable, Codable {
    public let jid: String
    public let score: Float

    public init(jid: String, score: Float) {
        self.jid = jid
        self.score = score
    }
}

public enum VerdictKind: String, Sendable, Codable {
    case verified
    case takeoverSuspected
    case impersonationSuspected
    case matchesUnsavedNumber
    case unknownVoice
    case unverifiable
    /// No longer produced. Kept so verdicts stored by older versions still decode.
    case unclear
}

public enum VerdictColour: String, Sendable, Codable {
    case green, red, amber, grey
}

/// The honest non-answers. There is no "inconclusive": either the note could be checked or it
/// could not, and each of these says exactly why not.
public enum UnverifiableReason: String, Sendable {
    case notEnrolled, modelFailed, mediaMissing, decodeFailed, tooShort
}

public struct Verdict: Sendable, Equatable {
    public let kind: VerdictKind
    public let colour: VerdictColour
    /// The fingerprint the headline score is measured against: the sender's own for a saved
    /// number, the claimed contact for an impersonation, or the closest match otherwise.
    public let comparedJID: String?
    public let score: Float?
    public let best: Comparison?
    public let reason: String?
    public let explanation: String

    public var isRed: Bool { colour == .red }

    public init(kind: VerdictKind, colour: VerdictColour, comparedJID: String?, score: Float?,
                best: Comparison?, reason: String?, explanation: String) {
        self.kind = kind
        self.colour = colour
        self.comparedJID = comparedJID
        self.score = score
        self.best = best
        self.reason = reason
        self.explanation = explanation
    }

    public static func unverifiable(_ reason: UnverifiableReason, explanation: String) -> Verdict {
        Verdict(kind: .unverifiable, colour: .grey, comparedJID: nil, score: nil, best: nil,
                reason: reason.rawValue, explanation: explanation)
    }
}

public struct VerificationInput: Sendable, Equatable {
    public let senderJID: String
    public let senderClass: SenderClass
    /// Set only for unsaved numbers whose profile name matches an enrolled contact.
    public let claimedJID: String?
    public let speechSeconds: Double
    /// Score against every fingerprint. Empty when no embedding could be produced.
    public let comparisons: [Comparison]
    public let names: [String: String]

    public init(senderJID: String, senderClass: SenderClass, claimedJID: String?, speechSeconds: Double,
                comparisons: [Comparison], names: [String: String]) {
        self.senderJID = senderJID
        self.senderClass = senderClass
        self.claimedJID = claimedJID
        self.speechSeconds = speechSeconds
        self.comparisons = comparisons
        self.names = names
    }
}
