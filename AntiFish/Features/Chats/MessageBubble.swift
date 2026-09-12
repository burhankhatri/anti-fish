import AntiFishCore
import SwiftUI

/// A WhatsApp-shaped bubble. Voice notes carry the verdict; everything else renders plainly so the
/// thread reads like the conversation it is.
struct MessageBubble: View {
    @Environment(AppModel.self) private var model
    let item: ThreadItem
    let showsSender: Bool

    var body: some View {
        HStack {
            if item.isFromMe { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                if showsSender, !item.isFromMe {
                    Text(item.senderName)
                        .font(AppType.captionSm)
                        .foregroundStyle(Color.primaryBlue)
                }
                content
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text(item.message.date.formatted(date: .omitted, time: .shortened))
                        .font(AppType.captionSm)
                        .foregroundStyle(Color.outlineColor)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: 440, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
                    .strokeBorder(Color.errorRed.opacity(item.needsAttention ? 0.45 : 0), lineWidth: 1.5))
            if !item.isFromMe { Spacer(minLength: 60) }
        }
        .accessibilityIdentifier("bubble.\(item.id)")
    }

    @ViewBuilder
    private var content: some View {
        switch item.message.kind {
        case .voiceNote:
            VoiceNoteBubble(item: item)
        case .text, .link:
            Text(item.message.text ?? "")
                .font(AppType.bodySm)
                .foregroundStyle(Color.onSurface)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .systemEvent:
            Text(item.message.text ?? "Group updated")
                .font(AppType.caption)
                .foregroundStyle(Color.onSurfaceVariant)
        case .deleted:
            Label("This message was deleted", systemImage: "slash.circle")
                .font(AppType.caption)
                .foregroundStyle(Color.outlineColor)
        default:
            Label(item.message.kind.placeholder, systemImage: symbol)
                .font(AppType.bodySm)
                .foregroundStyle(Color.onSurfaceVariant)
        }
    }

    private var symbol: String {
        switch item.message.kind {
        case .image: "photo"
        case .video: "video"
        case .sticker: "face.smiling"
        case .gif: "rectangle.stack.badge.play"
        case .document: "doc"
        default: "bubble.left"
        }
    }

    private var background: Color {
        if item.needsAttention { return .errorContainer }
        if item.isFromMe { return .primaryFixed }
        return .surfaceContainerLowest
    }
}

/// The point of the whole app: a voice note with what AntiFish makes of it.
struct VoiceNoteBubble: View {
    @Environment(AppModel.self) private var model
    let item: ThreadItem
    @State private var levels: [Float] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Button { if let url = model.mediaURL(for: item) { model.player.toggle(url: url) } } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.primaryContainer)
                }
                .buttonStyle(.plain)
                .disabled(item.message.relativeMediaPath == nil)

                Waveform(levels: levels.isEmpty ? Self.flat : levels,
                         progress: isPlaying || isCurrent ? model.player.progress : 0) { fraction in
                    if isCurrent { model.player.seek(to: fraction) }
                }
                .frame(width: 150)

                Text(duration)
                    .font(AppType.captionSm)
                    .monospacedDigit()
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            if let kind = item.verdictKind, let verdict = item.verdict {
                Button {
                    model.selectedItemID = item.id
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        VerdictPill(kind: kind, name: pillName(verdict))
                        Text(verdict.explanation)
                            .font(AppType.caption)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bubble.verdict.\(item.id)")
                // Anyone can be asked about, but it matters most for a number you have not saved.
                if !item.isFromMe, item.message.relativeMediaPath != nil {
                    ClaimPicker(item: item)
                }
            } else if !item.isFromMe, item.message.relativeMediaPath != nil {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("checking this voice…")
                        .font(AppType.caption)
                        .foregroundStyle(Color.outlineColor)
                }
            } else if item.message.relativeMediaPath == nil {
                Label("No audio on this Mac", systemImage: "waveform.slash")
                    .font(AppType.caption)
                    .foregroundStyle(Color.outlineColor)
            }
        }
        .task(id: item.id) {
            guard item.message.relativeMediaPath != nil else { return }
            levels = await model.waveform(forThread: item, bars: 28)
        }
    }

    private static let flat: [Float] = Array(repeating: 0.25, count: 28)

    private var isCurrent: Bool {
        model.player.currentURL != nil && model.player.currentURL == model.mediaURL(for: item)
    }

    private var isPlaying: Bool { model.player.isPlaying && isCurrent }

    private var duration: String {
        let s = item.message.durationSeconds
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func pillName(_ verdict: VerdictRecord) -> String {
        verdict.comparedJID.map { model.name(for: $0) } ?? item.senderName
    }
}
