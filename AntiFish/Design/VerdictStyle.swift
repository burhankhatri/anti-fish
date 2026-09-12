import AntiFishCore
import SwiftUI

/// One place that decides how each verdict looks and what it is called, so the pill, the bubble
/// and the flagged list never disagree.
enum VerdictStyle {
    static func title(_ kind: VerdictKind, name: String) -> String {
        switch kind {
        case .verified: "It's \(name)"
        case .takeoverSuspected: "Not \(name)"
        case .impersonationSuspected: "Not \(name)"
        case .matchesUnsavedNumber: "Sounds like \(name)"
        case .unknownVoice: "Voice you don't know"
        case .unverifiable, .unclear: "Can't check"
        }
    }

    static func symbol(_ kind: VerdictKind) -> String {
        switch kind {
        case .verified: "checkmark.seal.fill"
        case .takeoverSuspected, .impersonationSuspected: "exclamationmark.triangle.fill"
        case .matchesUnsavedNumber: "person.crop.circle.badge.questionmark"
        case .unknownVoice: "person.fill.questionmark"
        case .unverifiable, .unclear: "waveform.slash"
        }
    }

    static func foreground(_ kind: VerdictKind) -> Color {
        switch kind {
        case .verified: .onSuccessContainer
        case .takeoverSuspected, .impersonationSuspected: .onErrorContainer
        case .matchesUnsavedNumber: .onCautionContainer
        case .unknownVoice, .unverifiable, .unclear: .onSurfaceVariant
        }
    }

    static func container(_ kind: VerdictKind) -> Color {
        switch kind {
        case .verified: .successContainer
        case .takeoverSuspected, .impersonationSuspected: .errorContainer
        case .matchesUnsavedNumber: .cautionContainer
        case .unknownVoice, .unverifiable, .unclear: .surfaceContainerHigh
        }
    }

    /// Worth interrupting someone over.
    static func isAlarming(_ kind: VerdictKind) -> Bool {
        kind == .takeoverSuspected || kind == .impersonationSuspected
    }
}
