import AntiFishCore
import SwiftUI

struct ThreadView: View {
    @Environment(AppModel.self) private var model
    let chat: ChatRow

    private var groups: [(day: Date, items: [ThreadItem])] {
        Dictionary(grouping: model.thread, by: { Calendar.current.startOfDay(for: $0.message.date) })
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, items: $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if missingCount > 2 { downloadNotice }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(groups, id: \.day) { group in
                            DayDivider(day: group.day)
                            ForEach(group.items) { item in
                                MessageBubble(item: item, showsSender: chat.isGroup)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
                .onChange(of: model.thread.count) {
                    if let last = model.thread.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onAppear {
                    if let last = model.thread.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(Color.background)
        .accessibilityIdentifier("thread.view")
    }

    private var missingCount: Int {
        model.thread.filter { $0.isVoiceNote && !$0.isFromMe && $0.message.relativeMediaPath == nil }.count
    }

    /// WhatsApp Desktop only fetches media from the day it was linked, so most older notes have no
    /// audio here at all. Saying so is better than showing a row of silent bubbles.
    private var downloadNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.dotted").foregroundStyle(Color.outlineColor)
            Text("\(missingCount) older voice notes here have no audio on this Mac. WhatsApp only downloads media from the day it was linked, so there is nothing to listen to.")
                .font(AppType.caption)
                .foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.surfaceContainer)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Avatar(url: chat.avatarURL, name: chat.displayName, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(chat.displayName)
                    .font(AppType.bodyMedium)
                    .foregroundStyle(Color.onSurface)
                Text(subtitle)
                    .font(AppType.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            Spacer()
            if model.isLoadingThread {
                ProgressView().controlSize(.small)
                Text("checking voices…")
                    .font(AppType.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.surfaceContainerLowest)
    }

    private var subtitle: String {
        let incoming = model.thread.filter { $0.isVoiceNote && !$0.isFromMe }
        guard !incoming.isEmpty else { return chat.isGroup ? "Group" : "No voice notes here" }
        let flagged = model.thread.filter(\.needsAttention).count
        if flagged > 0 { return "\(flagged) voice note\(flagged == 1 ? "" : "s") to look at" }
        let playable = incoming.filter { $0.message.relativeMediaPath != nil }
        let checked = playable.filter { $0.verdict != nil }.count
        if playable.isEmpty {
            return "\(incoming.count) voice notes, none downloaded to this Mac"
        }
        if playable.count < incoming.count {
            return "\(checked) of \(playable.count) checked · \(incoming.count - playable.count) not downloaded"
        }
        return "\(checked) of \(playable.count) voice notes checked"
    }
}

struct DayDivider: View {
    let day: Date

    var body: some View {
        Text(label)
            .font(AppType.captionSm)
            .foregroundStyle(Color.onSurfaceVariant)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(Color.surfaceContainerHigh, in: Capsule())
            .padding(.vertical, Spacing.xs)
    }

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}
