import SwiftUI

struct FeedList: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Int64?

    private var groups: [(day: Date, items: [FeedItem])] {
        Dictionary(grouping: model.feed, by: \.day)
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, items: $0.value) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(groups, id: \.day) { group in
                Section(heading(for: group.day)) {
                    ForEach(group.items) { item in
                        FeedRow(item: item).tag(item.id)
                    }
                }
            }
        }
        .accessibilityIdentifier("feed.list")
        .overlay {
            if model.feed.isEmpty {
                ContentUnavailableView("No voice notes yet", systemImage: "waveform",
                                       description: Text("Incoming voice notes appear here with a verdict."))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.feed.map(\.id))
    }

    private func heading(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}
