import AntiFishCore
import SwiftUI

/// Tinted fill carries the meaning; the text stays neutral so a list of twenty rows stays still.
/// Red never appears here — it is reserved for the report action in the detail sheet.
struct VerdictPill: View {
    let kind: VerdictKind
    let name: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityIdentifier("verdict.pill")
            .accessibilityLabel(title)
    }

    var title: String {
        switch kind {
        case .verified: "Matches \(name)"
        case .takeoverSuspected: "Not \(name)'s voice"
        case .impersonationSuspected: "Not \(name)'s voice"
        case .matchesUnsavedNumber: "Sounds like \(name)"
        case .unknownVoice: "Unknown voice"
        case .unverifiable: "Not enough voice"
        case .unclear: "Inconclusive"
        }
    }

    private var symbol: String {
        switch kind {
        case .verified: "checkmark.seal.fill"
        case .takeoverSuspected, .impersonationSuspected: "exclamationmark.triangle.fill"
        case .matchesUnsavedNumber: "person.crop.circle.badge.questionmark"
        case .unknownVoice: "person.fill.questionmark"
        case .unverifiable: "questionmark.circle"
        case .unclear: "circle.dotted"
        }
    }

    private var tint: Color {
        switch kind {
        case .verified: .green
        case .takeoverSuspected, .impersonationSuspected, .matchesUnsavedNumber, .unclear: .orange
        case .unknownVoice, .unverifiable: .gray
        }
    }
}
