import AntiFishCore
import SwiftUI

/// A tinted capsule carrying the answer. Colour comes from `VerdictStyle`, so every surface agrees.
struct VerdictPill: View {
    let kind: VerdictKind
    let name: String
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: VerdictStyle.symbol(kind))
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text(VerdictStyle.title(kind, name: name))
                .font(compact ? AppType.captionSm : AppType.caption)
        }
        .foregroundStyle(VerdictStyle.foreground(kind))
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 2 : 4)
        .background(VerdictStyle.container(kind), in: Capsule())
        .accessibilityIdentifier("verdict.pill")
        .accessibilityLabel(VerdictStyle.title(kind, name: name))
    }
}
