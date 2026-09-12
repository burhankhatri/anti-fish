import SwiftUI

/// A roster, not a feed: tiers are plain grey text, no capsules. Row actions appear on hover,
/// which is what Finder and Mail do; swipe actions are not a macOS idiom.
struct ContactsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            section(.protected, footer: "Notification-eligible. Pin someone to keep them here.")
            section(.enrolled, footer: nil)
            section(.needsVoice, footer: "Fewer than three notes, or under 30 seconds of speech on this Mac.")
        }
        .accessibilityIdentifier("contacts.list")
        .frame(minWidth: 560, minHeight: 440)
        .animation(.snappy(duration: 0.25), value: model.contacts.map(\.id))
        .task { try? await model.refreshContacts() }
    }

    @ViewBuilder
    private func section(_ tier: ContactRow.Tier, footer: String?) -> some View {
        let rows = model.contacts.filter { $0.tier == tier }
        Section {
            ForEach(rows) { ContactRowView(row: $0) }
        } header: {
            HStack(spacing: 6) {
                Text(tier.title)
                Text("\(rows.count)").foregroundStyle(.secondary)
            }
            .font(.headline)
        } footer: {
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ContactRowView: View {
    @Environment(AppModel.self) private var model
    let row: ContactRow
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: row.avatarURL, name: row.name)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if row.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Text(row.name).font(.body.weight(.medium))
                    if !row.isSaved {
                        Text("not in your contacts").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 5) {
                    if row.tier == .needsVoice {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if row.tier != .needsVoice {
                    Button { Task { await model.togglePin(row) } } label: {
                        Image(systemName: row.pinned ? "pin.slash" : "pin")
                    }
                    .help(row.pinned ? "Unpin" : "Pin as protected")
                    .accessibilityIdentifier("contacts.pin.\(row.jid)")
                }
                Button { Task { await model.remove(row) } } label: {
                    Image(systemName: "minus.circle")
                }
                .help("Remove and stop enrolling")
                .accessibilityIdentifier("contacts.remove.\(row.jid)")
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if row.tier != .needsVoice {
                Button(row.pinned ? "Unpin" : "Pin as protected") { Task { await model.togglePin(row) } }
            }
            Button("Remove", role: .destructive) { Task { await model.remove(row) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contacts.row.\(row.jid)")
    }

    private var detail: String {
        guard row.tier != .needsVoice else { return "\(row.noteCount) notes so far" }
        let last = row.lastNoteDate?.formatted(date: .abbreviated, time: .omitted) ?? "—"
        return "\(row.noteCount) notes · \(Int(row.speechSeconds)) s of speech · last \(last)"
    }
}
