import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            FeedList(selection: $model.selectedItemID)
                .safeAreaInset(edge: .top, spacing: 0) { HeaderBar() }
                .toolbar {
                    ToolbarItem {
                        Button { openWindow(id: "contacts") } label: {
                            Label("Contacts", systemImage: "person.2")
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

struct HeaderBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(model.statusLine).font(.callout)
                if model.isProcessing {
                    ProgressView().controlSize(.small)
                    Text("analysing…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityIdentifier("header.status")

            if let banner = model.banner {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(banner).lineLimit(2)
                    Spacer()
                    Button("Dismiss") { model.banner = nil }.buttonStyle(.borderless)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(.bar)
        .animation(.snappy(duration: 0.25), value: model.banner)
    }

    private var dot: Color {
        if model.isPaused { return .orange }
        return model.lastNeedingAttention == nil ? .green : .orange
    }
}
