import Foundation

/// How much speech a note needs before it is worth judging at all.
public enum SpeechGates {
    /// Below this there is nothing to listen to, and saying so is not the same as being unsure.
    public static let minSpeech = 2.0
}

/// Turns one similarity score into something a person can act on.
///
/// There is no middle. A note either sounds like the person or it does not, measured against a
/// threshold learned from the user's own contacts. The only non-answers are the honest ones: no
/// audio, or too little speech.
public enum Verifier {
    public static func verdict(_ input: VerificationInput, thresholds t: Thresholds) -> Verdict {
        let name = { (jid: String) in input.names[jid] ?? NameResolver.fallbackName(for: jid) }
        let sender = name(input.senderJID)

        if input.speechSeconds < SpeechGates.minSpeech {
            let speech = String(format: "%.1f", input.speechSeconds)
            return .unverifiable(.tooShort,
                                 explanation: "Too short to check — only \(speech) s of speech.")
        }
        if input.senderClass == .knownUnenrolled {
            return .unverifiable(.notEnrolled,
                                 explanation: "Not enough of \(sender)'s voice yet to compare against.")
        }
        guard let best = input.comparisons.max(by: { $0.score < $1.score }) else {
            return .unverifiable(.modelFailed, explanation: "Couldn\'t pick a voice out of this note.")
        }

        switch input.senderClass {
        case .knownEnrolled:
            guard let own = input.comparisons.first(where: { $0.jid == input.senderJID }) else {
                return .unverifiable(.notEnrolled,
                                     explanation: "Not enough of \(sender)\'s voice yet to compare against.")
            }
            if own.score >= t.decision {
                return Verdict(kind: .verified, colour: .green, comparedJID: own.jid, score: own.score,
                               best: best, reason: nil,
                               explanation: "This is \(sender).")
            }
            var text = "Sent from \(sender)\'s number, but it does not sound like \(sender)."
            if best.jid != own.jid, best.score >= t.decision {
                text += " It sounds like \(name(best.jid))."
            }
            return Verdict(kind: .takeoverSuspected, colour: .red, comparedJID: own.jid, score: own.score,
                           best: best, reason: nil, explanation: text)

        case .unknown:
            // When the user names someone, that is the question. Answering about whoever happens
            // to score highest instead told one user "This really is Shifa" when they had asked
            // about Momina.
            if let claimedJID = input.claimedJID {
                guard let claimed = input.comparisons.first(where: { $0.jid == claimedJID }) else {
                    return .unverifiable(.notEnrolled,
                                         explanation: "There isn't enough of \(name(claimedJID))'s voice saved to compare against.")
                }
                if claimed.score >= t.decision {
                    var text = "This does sound like \(name(claimed.jid)). The number is not saved, so confirm on the number you already have."
                    if best.jid != claimed.jid, best.score > claimed.score + 0.1 {
                        text += " It sounds even more like \(name(best.jid))."
                    }
                    return Verdict(kind: .matchesUnsavedNumber, colour: .amber, comparedJID: claimed.jid,
                                   score: claimed.score, best: best, reason: nil, explanation: text)
                }
                var text = "This does not sound like \(name(claimed.jid))."
                if best.jid != claimed.jid, best.score >= t.decision {
                    text += " It sounds more like \(name(best.jid))."
                }
                return Verdict(kind: .impersonationSuspected, colour: .red, comparedJID: claimed.jid,
                               score: claimed.score, best: best, reason: nil, explanation: text)
            }

            if best.score >= t.decision {
                return Verdict(kind: .matchesUnsavedNumber, colour: .amber, comparedJID: best.jid,
                               score: best.score, best: best, reason: nil,
                               explanation: "Sounds like \(name(best.jid)), from a number you have not saved. Check with \(name(best.jid)) on their own number first.")
            }
            return Verdict(kind: .unknownVoice, colour: .grey, comparedJID: best.jid, score: best.score,
                           best: best, reason: nil,
                           explanation: "Not a voice you have heard before.")

        case .knownUnenrolled:
            return .unverifiable(.notEnrolled,
                                 explanation: "Not enough of \(sender)\'s voice yet to compare against.")
        }
    }
}
