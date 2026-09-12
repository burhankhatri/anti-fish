import SwiftUI

struct FeedRow: View {
    @Environment(AppModel.self) private var model
    let item: FeedItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Avatar(url: item.avatarURL, name: item.senderName)
                if hovering {
                    Circle().fill(.black.opacity(0.45)).frame(width: 32, height: 32)
                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Circle())
            .onTapGesture { model.player.toggle(url: model.mediaURL(for: item)) }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.senderName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if let chat = item.chatName {
                        Text("in \(chat)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Text(duration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(item.record.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if item.showsPill {
                VerdictPill(kind: item.kind, name: pillName)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            Text(item.record.date.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .background(item.needsAttention ? Color.orange.opacity(0.07) : .clear)
        .animation(.snappy(duration: 0.22), value: item.kind)
        .onHover { hovering = $0 }
        .accessibilityIdentifier("feed.row.\(item.id)")
    }

    private var isPlayingThis: Bool {
        model.player.isPlaying && model.player.currentURL == model.mediaURL(for: item)
    }

    private var duration: String {
        let s = item.record.durationSeconds
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var pillName: String {
        item.record.comparedJID.map { model.name(for: $0) } ?? item.senderName
    }
}
