import Foundation

/// How much speech a verdict needs before it is worth saying out loud.
public enum SpeechGates {
    /// Below this there is nothing to judge.
    public static let minSpeech = 1.5
    /// Accusing someone of impersonation needs more evidence than clearing them.
    public static let minForRed = 3.0
    public static let minForVerified = 2.0
}

/// Turns similarity scores into something a person can act on.
public enum Verifier {
    public static func verdict(_ input: VerificationInput, thresholds t: Thresholds) -> Verdict {
        let name = { (jid: String) in input.names[jid] ?? NameResolver.fallbackName(for: jid) }
        let sender = name(input.senderJID)
        let speech = String(format: "%.1f", input.speechSeconds)

        if input.speechSeconds < SpeechGates.minSpeech {
            return unclear(.tooShort, compared: nil, score: nil, best: nil,
                           "Too short to verify: only \(speech) s of speech.")
        }
        if input.senderClass == .knownUnenrolled {
            return .unverifiable(.notEnrolled, explanation: "Not enough voice history from \(sender) to verify yet.")
        }
        guard let best = input.comparisons.max(by: { $0.score < $1.score }) else {
            return .unverifiable(.modelFailed, explanation: "Couldn't extract a voice from this note.")
        }
        let tooShortToAccuse = input.speechSeconds < SpeechGates.minForRed

        switch input.senderClass {
        case .knownEnrolled:
            guard let own = input.comparisons.first(where: { $0.jid == input.senderJID }) else {
                return .unverifiable(.notEnrolled, explanation: "Not enough voice history from \(sender) to verify yet.")
            }
            if own.score >= t.match {
                if input.speechSeconds < SpeechGates.minForVerified {
                    return unclear(.shortClip, compared: own.jid, score: own.score, best: best,
                                   "Sounds like \(sender), but the clip is short (\(speech) s).")
                }
                return Verdict(kind: .verified, colour: .green, comparedJID: own.jid, score: own.score,
                               best: best, reason: nil,
                               explanation: "Voice matches \(sender)'s fingerprint.")
            }
            if own.score <= t.reject {
                if tooShortToAccuse {
                    return unclear(.shortClip, compared: own.jid, score: own.score, best: best,
                                   "The voice does not look like \(sender)'s, but the clip is short (\(speech) s).")
                }
                var text = "Sent from \(sender)'s number, but the voice does not match \(sender)'s fingerprint."
                if best.jid != own.jid, best.score >= t.match {
                    text += " Closest known voice: \(name(best.jid))."
                }
                return Verdict(kind: .takeoverSuspected, colour: .red, comparedJID: own.jid, score: own.score,
                               best: best, reason: nil, explanation: text)
            }
            return unclear(.borderline, compared: own.jid, score: own.score, best: best,
                           "The voice is inconclusive for \(sender).")

        case .unknown:
            let claimed = input.claimedJID.flatMap { jid in input.comparisons.first { $0.jid == jid } }
            if let claimed, claimed.score <= t.reject {
                if tooShortToAccuse {
                    return unclear(.shortClip, compared: claimed.jid, score: claimed.score, best: best,
                                   "Profile name says \(name(claimed.jid)) and the voice does not look like theirs, but the clip is short (\(speech) s).")
                }
                return Verdict(kind: .impersonationSuspected, colour: .red, comparedJID: claimed.jid,
                               score: claimed.score, best: best, reason: nil,
                               explanation: "Profile name says \(name(claimed.jid)), but the voice does not match \(name(claimed.jid))'s fingerprint.")
            }
            if best.score >= t.match {
                var text = "Voice matches \(name(best.jid)), but this number is not saved. Confirm on \(name(best.jid))'s saved number before acting."
                if let claimed, claimed.jid != best.jid {
                    text += " Profile name says \(name(claimed.jid))."
                }
                return Verdict(kind: .matchesUnsavedNumber, colour: .amber, comparedJID: best.jid,
                               score: best.score, best: best, reason: nil, explanation: text)
            }
            if let claimed {
                return unclear(.borderline, compared: claimed.jid, score: claimed.score, best: best,
                               "Profile name says \(name(claimed.jid)); the voice is inconclusive.")
            }
            return Verdict(kind: .unknownVoice, colour: .grey, comparedJID: nil, score: nil, best: best,
                           reason: nil, explanation: "Voice does not match anyone you know.")

        case .knownUnenrolled:
            return .unverifiable(.notEnrolled, explanation: "Not enough voice history from \(sender) to verify yet.")
        }
    }

    private static func unclear(_ reason: UnclearReason, compared: String?, score: Float?,
                                best: Comparison?, _ explanation: String) -> Verdict {
        Verdict(kind: .unclear, colour: .amber, comparedJID: compared, score: score, best: best,
                reason: reason.rawValue, explanation: explanation)
    }
}
