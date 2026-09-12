import AntiFishCore
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
                ChatRowView(chat: chat)
                    .tag(chat.id)
                    .contextMenu {
                        Button("Hide chat") { Task { await model.hideChat(chat) } }
                    }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceContainerLow)
        .searchable(text: $model.chatSearch, placement: .sidebar, prompt: "Search chats")
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $model.chatOrder) {
                    ForEach(ChatOrder.allCases) { Text($0.title).font(AppType.captionSm).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("chat.order")
                if model.hiddenChatCount > 0 {
                    Button {
                        Task { await model.unhideAllChats() }
                    } label: {
                        Label("\(model.hiddenChatCount)", systemImage: "eye.slash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Show hidden chats again")
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.surfaceContainerLow)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.outlineVariant.opacity(0.45)).frame(height: 1)
            }
        }
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
                            .foregroundStyle(Color.outlineColor)
                    }
                    Text(chat.displayName)
                        .font(AppType.bodySmMedium)
                        .foregroundStyle(Color.onSurface)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let date = chat.lastMessageDate {
                        Text(Self.stamp(date))
                            .font(AppType.captionSm)
                            .foregroundStyle(Color.outlineColor)
                    }
                }
                HStack(spacing: 6) {
                    Text(chat.preview.isEmpty ? " " : chat.preview)
                        .font(AppType.caption)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if chat.summary.voiceNoteCount > 0 {
                        Label("\(chat.summary.voiceNoteCount)", systemImage: "waveform")
                            .font(AppType.captionSm)
                            .foregroundStyle(Color.outlineColor)
                            .labelStyle(.titleAndIcon)
                            .help("\(chat.summary.voiceNoteCount) of \(chat.summary.voiceNoteTotal) voice notes have audio on this Mac")
                    } else if chat.summary.hasNoPlayableAudio {
                        Label("\(chat.summary.voiceNoteTotal)", systemImage: "waveform.slash")
                            .font(AppType.captionSm)
                            .foregroundStyle(Color.surfaceDim)
                            .labelStyle(.titleAndIcon)
                            .help("\(chat.summary.voiceNoteTotal) voice notes, none downloaded to this Mac")
                    }
                    if chat.attentionCount > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.errorRed)
                    }
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(AppType.captionSm)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primaryContainer, in: Capsule())
                            .foregroundStyle(Color.onPrimary)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.base)
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
