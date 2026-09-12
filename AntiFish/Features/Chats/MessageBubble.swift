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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                content
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text(item.message.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 420, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.orange.opacity(item.needsAttention ? 0.55 : 0), lineWidth: 1.5))
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
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .systemEvent:
            Text(item.message.text ?? "Group updated")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .deleted:
            Label("This message was deleted", systemImage: "slash.circle")
                .font(.callout.italic())
                .foregroundStyle(.tertiary)
        default:
            Label(item.message.kind.placeholder, systemImage: symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
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

    private var background: AnyShapeStyle {
        if item.needsAttention { return AnyShapeStyle(.orange.opacity(0.10)) }
        if item.isFromMe { return AnyShapeStyle(.tint.opacity(0.16)) }
        return AnyShapeStyle(.quaternary.opacity(0.55))
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
                        .font(.system(size: 26))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .disabled(item.message.relativeMediaPath == nil)

                Waveform(levels: levels.isEmpty ? Self.flat : levels,
                         progress: isPlaying || isCurrent ? model.player.progress : 0) { fraction in
                    if isCurrent { model.player.seek(to: fraction) }
                }
                .frame(width: 150)

                Text(duration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let kind = item.verdictKind, let verdict = item.verdict {
                Button {
                    model.selectedItemID = item.id
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        VerdictPill(kind: kind, name: pillName(verdict))
                        Text(verdict.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bubble.verdict.\(item.id)")
            } else if !item.isFromMe, item.message.relativeMediaPath != nil {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("checking this voice…").font(.caption).foregroundStyle(.tertiary)
                }
            } else if item.message.relativeMediaPath == nil {
                Label("No audio on this Mac — nothing to check", systemImage: "waveform.slash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
