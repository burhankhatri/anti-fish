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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: model.thread.count) {
                    if let last = model.thread.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onAppear {
                    if let last = model.thread.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(.background)
        .accessibilityIdentifier("thread.view")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Avatar(url: chat.avatarURL, name: chat.displayName, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(chat.displayName).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoadingThread {
                ProgressView().controlSize(.small)
                Text("checking voices…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var subtitle: String {
        let checked = model.thread.filter { $0.verdict != nil }.count
        let notes = model.thread.filter { $0.isVoiceNote && !$0.isFromMe }.count
        guard notes > 0 else { return chat.isGroup ? "Group" : "No voice notes here" }
        let flagged = model.thread.filter(\.needsAttention).count
        if flagged > 0 { return "\(flagged) voice note\(flagged == 1 ? "" : "s") to look at" }
        return "\(checked) of \(notes) voice notes checked"
    }
}

struct DayDivider: View {
    let day: Date

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.6), in: Capsule())
            .padding(.vertical, 8)
    }

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}
