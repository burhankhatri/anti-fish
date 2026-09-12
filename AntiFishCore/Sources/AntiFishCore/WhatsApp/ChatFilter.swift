import Foundation

/// Which chats to show. Groups and one-to-one conversations answer different questions, and mixing
/// them means scrolling past twenty group threads to reach the person who just sent you something.
public enum ChatFilter: String, Sendable, CaseIterable, Identifiable {
    case everyone, people, groups

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .everyone: "All"
        case .people: "People"
        case .groups: "Groups"
        }
    }

    public var symbol: String {
        switch self {
        case .everyone: "tray.full"
        case .people: "person"
        case .groups: "person.2"
        }
    }

    public func apply(to chats: [ChatSummary]) -> [ChatSummary] {
        switch self {
        case .everyone: chats
        case .people: chats.filter { !$0.isGroup }
        case .groups: chats.filter(\.isGroup)
        }
    }
}
