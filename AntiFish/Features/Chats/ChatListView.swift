import SwiftUI

struct ChatListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(
            get: { model.selectedChatPK },
            set: { pk in
                if let pk, let chat = model.chats.first(where: { $0.id == pk }) {
                    Task { await model.openChat(chat) }
                }
            })) {
            ForEach(model.visibleChats) { chat in
                ChatRowView(chat: chat).tag(chat.id)
            }
        }
        .searchable(text: $model.chatSearch, placement: .sidebar, prompt: "Search chats")
        .accessibilityIdentifier("chat.list")
        .overlay {
            if model.chats.isEmpty {
                ContentUnavailableView("No chats", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Your WhatsApp chats appear here."))
            }
        }
    }
}

struct ChatRowView: View {
    let chat: ChatRow

    var body: some View {
        HStack(spacing: 10) {
            Avatar(url: chat.avatarURL, name: chat.displayName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if chat.isGroup {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Text(chat.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let date = chat.lastMessageDate {
                        Text(Self.stamp(date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 6) {
                    Text(chat.preview.isEmpty ? " " : chat.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if chat.attentionCount > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.tint, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("chat.row.\(chat.id)")
    }

    /// WhatsApp's own stamp: time today, "Yesterday", then a date.
    static func stamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
