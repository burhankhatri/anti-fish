import AntiFishCore
import SwiftUI

/// A WhatsApp-shaped bubble. Voice notes carry the verdict; everything else renders plainly so the
/// thread reads like the conversation it is.
struct MessageBubble: View {
    @Environment(AppModel.self) private var model
    let item: ThreadItem
    let showsSender: Bool

    var body: some View {
        HStack(spacing: 0) {
            if item.isFromMe { Spacer(minLength: 48) }
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
            .frame(minWidth: item.needsFixedWidth ? 300 : nil,
                   maxWidth: item.needsFixedWidth ? 340 : 460,
                   alignment: .leading)
            .fixedSize(horizontal: !item.needsFixedWidth, vertical: false)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
                    .strokeBorder(borderColour, lineWidth: item.needsAttention ? 1.5 : 1))
            if !item.isFromMe { Spacer(minLength: 48) }
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
        case .image, .gif:
            ImageBubble(item: item)
        case .video:
            VideoBubble(item: item)
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
        return item.isFromMe ? .primaryFixed : .surfaceContainerLowest
    }

    /// Incoming bubbles are white on a near-white page, so they need an edge to exist at all.
    private var borderColour: Color {
        if item.needsAttention { return .errorRed.opacity(0.5) }
        return item.isFromMe ? .primaryFixedDim.opacity(0.7) : .outlineVariant.opacity(0.55)
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

/// A shared picture, and the one question worth asking about it: was this made by a machine?
struct ImageBubble: View {
    @Environment(AppModel.self) private var model
    let item: ThreadItem

    private var verdict: ImageVerdict? { model.imageVerdicts[item.id] }
    private var isChecking: Bool { model.imageCheckInFlight == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let url = model.mediaURL(for: item), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 240, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                Label("Photo not downloaded", systemImage: "photo")
                    .font(AppType.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            if let verdict {
                HStack(spacing: 5) {
                    Image(systemName: verdict.isAlarming ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(verdict.kind.title).font(AppType.captionSm)
                    Text("\(Int(verdict.confidence * 100))%")
                        .font(AppType.captionSm)
                        .monospacedDigit()
                        .opacity(0.75)
                }
                .foregroundStyle(verdict.isAlarming ? Color.onErrorContainer : Color.onSuccessContainer)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(verdict.isAlarming ? Color.errorContainer : Color.successContainer,
                            in: Capsule())
            } else if isChecking {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("checking this picture…")
                        .font(AppType.captionSm)
                        .foregroundStyle(Color.outlineColor)
                }
            } else if model.imageCheckAvailable, model.mediaURL(for: item) != nil {
                Button {
                    Task { await model.checkImage(item) }
                } label: {
                    Label("Is this real?", systemImage: "sparkle.magnifyingglass")
                        .font(AppType.captionSm)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("image.check.\(item.id)")
            }
        }
    }
}

/// A shared clip, and whether the frames inside it were made by a machine.
struct VideoBubble: View {
    @Environment(AppModel.self) private var model
    let item: ThreadItem

    private var verdict: VideoVerdict? { model.videoVerdicts[item.id] }
    private var isChecking: Bool { model.videoCheckInFlight == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.primaryContainer)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Video").font(AppType.bodySm).foregroundStyle(Color.onSurface)
                    if item.message.durationSeconds > 0 {
                        Text("\(item.message.durationSeconds)s")
                            .font(AppType.captionSm)
                            .foregroundStyle(Color.outlineColor)
                    }
                }
            }

            if let verdict {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: verdict.isAlarming
                              ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(verdict.image.kind.title).font(AppType.captionSm)
                    }
                    .foregroundStyle(verdict.isAlarming ? Color.onErrorContainer : Color.onSuccessContainer)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(verdict.isAlarming ? Color.errorContainer : Color.successContainer,
                                in: Capsule())
                    Text(verdict.summary)
                        .font(AppType.captionSm)
                        .foregroundStyle(Color.outlineColor)
                }
            } else if isChecking {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("checking the frames…")
                        .font(AppType.captionSm)
                        .foregroundStyle(Color.outlineColor)
                }
            } else if model.videoCheckAvailable, model.mediaURL(for: item) != nil {
                Button {
                    Task { await model.checkVideo(item) }
                } label: {
                    Label("Is this real?", systemImage: "sparkle.magnifyingglass")
                        .font(AppType.captionSm)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("video.check.\(item.id)")
            }
        }
    }
}
