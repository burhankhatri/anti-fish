import SwiftUI

/// What the app is looking at. Overlap puts the same switch at the foot of its sidebar.
enum AppSource: String, CaseIterable, Identifiable, Sendable {
    case whatsapp, mail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .mail: "Email"
        }
    }

    var symbol: String {
        switch self {
        case .whatsapp: "bubble.left.and.bubble.right.fill"
        case .mail: "envelope.fill"
        }
    }
}

/// The switch itself: two big targets, named in words, at the foot of the sidebar.
struct SourceSwitcher: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(AppSource.allCases) { source in
                Button {
                    model.source = source
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: source.symbol)
                            .font(.system(size: 17, weight: .medium))
                        Text(source.title)
                            .font(AppType.captionSm)
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .padding(.vertical, Spacing.xs)
                    .background(model.source == source ? Color.primaryFixed : Color.clear,
                                in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                    .foregroundStyle(model.source == source ? Color.primaryBlue : Color.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("source.\(source.rawValue)")
                .badge(source == .mail ? model.dangerMailCount : 0)
            }
        }
        .padding(Spacing.xs)
        .background(Color.surfaceContainer)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.outlineVariant.opacity(0.5)).frame(height: 1)
        }
        .animation(.snappy(duration: 0.2), value: model.source)
    }
}
