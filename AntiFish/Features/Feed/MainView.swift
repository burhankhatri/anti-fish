import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var showsFlaggedOnly = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            ChatListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
                .safeAreaInset(edge: .top, spacing: 0) { StatusStrip() }
        } detail: {
            if let chat = model.selectedChat {
                ThreadView(chat: chat)
            } else {
                ContentUnavailableView("Pick a chat",
                                       systemImage: "waveform.badge.magnifyingglass",
                                       description: Text("Open a conversation and AntiFish checks the voice notes in it."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button { openWindow(id: "flagged") } label: {
                    Label("Flagged", systemImage: "exclamationmark.triangle")
                }
                .badge(model.feed.filter(\.needsAttention).count)
                .accessibilityIdentifier("main.flagged")
            }
            ToolbarItem {
                Button { openWindow(id: "contacts") } label: {
                    Label("Voices", systemImage: "person.2")
                }
                .accessibilityIdentifier("main.contacts")
            }
            ToolbarItem {
                Button { model.setPaused(!model.isPaused) } label: {
                    Label(model.isPaused ? "Resume" : "Pause",
                          systemImage: model.isPaused ? "play.fill" : "pause.fill")
                }
                .accessibilityIdentifier("main.pause")
            }
        }
        .sheet(item: selectedItem) { item in
            DetailSheet(item: item)
        }
    }

    private var selectedItem: Binding<FeedItem?> {
        Binding(
            get: { model.feed.first { $0.id == model.selectedItemID } },
            set: { model.selectedItemID = $0?.id })
    }
}

/// A thin line above the chat list: what AntiFish is doing, and anything that went wrong.
struct StatusStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(model.statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if model.isProcessing { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityIdentifier("header.status")

            if let banner = model.banner {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(banner).lineLimit(3).font(.caption)
                    Spacer()
                    Button("Dismiss") { model.banner = nil }.buttonStyle(.borderless).font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(.bar)
        .animation(.snappy(duration: 0.25), value: model.banner)
    }

    private var dot: Color {
        if model.isPaused { return .orange }
        return model.feed.contains(where: \.needsAttention) ? .orange : .green
    }
}

/// Everything AntiFish wants looked at, across every chat.
struct FlaggedView: View {
    @Environment(AppModel.self) private var model

    private var items: [FeedItem] {
        model.feed.filter { $0.showsPill }
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedItemID) {
            ForEach(items) { item in
                FeedRow(item: item).tag(item.id)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .accessibilityIdentifier("feed.list")
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing to look at", systemImage: "checkmark.shield",
                                       description: Text("Voice notes worth a second look appear here."))
            }
        }
        .sheet(item: Binding(
            get: { model.feed.first { $0.id == model.selectedItemID } },
            set: { model.selectedItemID = $0?.id })) { item in
            DetailSheet(item: item)
        }
    }
}
