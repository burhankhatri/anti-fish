import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(model.statusLine).font(.callout.weight(.medium)).lineLimit(1)
                Spacer()
            }
            Divider()

            if model.feed.isEmpty {
                Text("No voice notes yet").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.feed.prefix(3)) { item in
                Button {
                    model.selectedItemID = item.id
                    openMain()
                } label: {
                    HStack(spacing: 8) {
                        Text(item.senderName).lineLimit(1)
                        Spacer()
                        if item.showsPill {
                            VerdictPill(kind: item.kind, name: pillName(item))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()
            HStack {
                Button("Open AntiFish") { openMain() }
                    .accessibilityIdentifier("menubar.open")
                Spacer()
                Button(model.isPaused ? "Resume" : "Pause") { model.setPaused(!model.isPaused) }
                    .accessibilityIdentifier("menubar.pause")
                Button("Quit") { NSApp.terminate(nil) }
                    .accessibilityIdentifier("menubar.quit")
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 340)
    }

    private var dot: Color {
        if model.isPaused { return .orange }
        return model.lastNeedingAttention == nil ? .green : .orange
    }

    private func pillName(_ item: FeedItem) -> String {
        item.record.comparedJID.map { model.name(for: $0) } ?? item.senderName
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
