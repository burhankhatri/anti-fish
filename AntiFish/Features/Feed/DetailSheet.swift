import AntiFishCore
import SwiftUI

/// States facts and hands the judgment back. Neither action is a filled red button: the dangerous
/// one is red text, the ordinary one is prominent.
struct DetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: FeedItem
    @State private var levels: [Float] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            identityCard
            verdictLine
            if let score = item.record.score {
                ScoreMeterView(score: Float(score), thresholds: model.thresholds,
                               errorRate: model.calibration?.errorRate ?? 0)
            }
            if !comparisons.isEmpty { evidence }
            Spacer(minLength: 0)
            actions
        }
        .padding(Spacing.lg)
        .frame(width: 540, height: 660)
        .background(Color.background)
        .accessibilityIdentifier("detail.pane")
        .task(id: item.id) {
            model.player.stop()
            levels = await model.waveform(for: item)
        }
        .onDisappear { model.player.stop() }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(url: item.avatarURL, name: item.senderName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.senderName)
                        .font(AppType.title)
                        .foregroundStyle(Color.onSurface)
                    Text(subtitle)
                        .font(AppType.caption)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                Button {
                    model.player.toggle(url: model.mediaURL(for: item))
                } label: {
                    Image(systemName: model.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.primaryContainer)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.play")

                Waveform(levels: levels, progress: model.player.progress) { model.player.seek(to: $0) }

                Text(timeLabel)
                    .font(AppType.captionSm)
                    .monospacedDigit()
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceContainerLowest,
                    in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
    }

    private var verdictLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.record.explanation)
                .font(AppType.subheading)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Text(basis)
                .font(AppType.bodySm)
                .foregroundStyle(Color.onSurfaceVariant)
        }
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Closest voices you know")
                .font(AppType.bodySmMedium)
                .foregroundStyle(Color.onSurface)
            ForEach(comparisons, id: \.jid) { c in
                HStack {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)
                    Text(model.name(for: c.jid))
                    Spacer()
                    Text(c.score, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                }
                .font(AppType.bodySm)
                .foregroundStyle(Color.onSurfaceVariant)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Report impostor") {
                Task { await model.reportImpostor(item); dismiss() }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.errorRed)
            .font(AppType.bodySmMedium)
            .accessibilityIdentifier("detail.impostor")

            Spacer()

            Button("Yes, this is really \(item.senderName)") {
                Task { await model.markGenuine(item); dismiss() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.primaryContainer)
            .font(AppType.bodySmMedium)
            .accessibilityIdentifier("detail.genuine")
        }
        .controlSize(.large)
    }

    private var comparisons: [Comparison] {
        var list: [Comparison] = []
        if let jid = item.record.comparedJID, let score = item.record.score {
            list.append(Comparison(jid: jid, score: Float(score)))
        }
        if let jid = item.record.bestJID, let score = item.record.bestScore, jid != item.record.comparedJID {
            list.append(Comparison(jid: jid, score: Float(score)))
        }
        return list
    }

    private var subtitle: String {
        var parts = [item.record.date.formatted(date: .abbreviated, time: .shortened)]
        if let chat = item.chatName { parts.append("in \(chat)") }
        return parts.joined(separator: " · ")
    }

    private var basis: String {
        let speech = String(format: "%.1f", item.record.speechSeconds)
        guard let jid = item.record.comparedJID,
              let row = model.contacts.first(where: { $0.jid == jid }), row.noteCount > 0 else {
            return "Based on \(speech) s of speech in this note."
        }
        return "Based on \(speech) s of speech, compared against \(row.noteCount) of \(row.name)'s notes."
    }

    private var timeLabel: String {
        let d = model.player.currentURL == model.mediaURL(for: item) ? model.player.duration : Double(item.record.durationSeconds)
        let e = model.player.currentURL == model.mediaURL(for: item) ? model.player.elapsed : 0
        return String(format: "%d:%02d / %d:%02d", Int(e) / 60, Int(e) % 60, Int(d) / 60, Int(d) % 60)
    }
}
