import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var showsFlaggedOnly = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Group {
                switch model.source {
                case .whatsapp: ChatListView()
                case .mail: MailListView()
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            .safeAreaInset(edge: .top, spacing: 0) { StatusStrip() }
            .safeAreaInset(edge: .bottom, spacing: 0) { SourceSwitcher() }
        } detail: {
            if model.source == .mail {
                if let mail = model.selectedMail {
                    MailDetailView(message: mail)
                } else {
                    emptyDetail(title: "Pick a message",
                                detail: "Open an email and AntiFish shows what it found.",
                                symbol: "envelope.badge.shield.half.filled")
                }
            } else if let chat = model.selectedChat {
                ThreadView(chat: chat)
            } else {
                emptyDetail(title: "Pick a chat",
                            detail: "Open a conversation and AntiFish checks the voice notes in it.",
                            symbol: "waveform.badge.magnifyingglass")
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

    private func emptyDetail(title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.outlineVariant)
            Text(title).font(AppType.headingSm).foregroundStyle(Color.onSurface)
            Text(detail)
                .font(AppType.bodySm)
                .foregroundStyle(Color.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.background)
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
                Text(model.statusLine)
                    .font(AppType.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .lineLimit(1)
                Spacer()
                if model.isProcessing { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .accessibilityIdentifier("header.status")

            if let banner = model.banner {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(banner).lineLimit(3).font(AppType.caption)
                    Spacer()
                    Button("Dismiss") { model.banner = nil }
                        .buttonStyle(.borderless)
                        .font(AppType.caption)
                }
                .foregroundStyle(Color.onErrorContainer)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color.errorContainer)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.surfaceContainerLow)
        .animation(.snappy(duration: 0.25), value: model.banner)
    }

    private var dot: Color {
        if model.isPaused { return .secondaryContainer }
        return model.feed.contains(where: \.needsAttention) ? .errorRed : .successGreen
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
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.successGreen)
                    Text("Nothing to look at")
                        .font(AppType.title)
                        .foregroundStyle(Color.onSurface)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.background)
            }
        }
        .sheet(item: Binding(
            get: { model.feed.first { $0.id == model.selectedItemID } },
            set: { model.selectedItemID = $0?.id })) { item in
            DetailSheet(item: item)
        }
    }
}
