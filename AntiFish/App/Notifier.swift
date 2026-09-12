import Foundation
import UserNotifications

/// Only a suspected impersonation interrupts the user. A verified note is good news and can wait.
@MainActor
final class Notifier {
    private let center = UNUserNotificationCenter.current()
    private(set) var isAuthorized = false

    func requestAuthorization() async -> Bool {
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            isAuthorized = false
        }
        return isAuthorized
    }

    func refreshAuthorization() async {
        isAuthorized = await center.notificationSettings().authorizationStatus == .authorized
    }

    static func shouldNotify(_ item: FeedItem) -> Bool { item.needsAttention }

    static func content(for item: FeedItem) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.kind == .takeoverSuspected ? "Possible account takeover" : "Possible impersonation"
        content.body = "\(item.senderName): \(item.record.explanation)"
        content.sound = .default
        content.userInfo = ["messagePK": item.id]
        return content
    }

    func notify(_ item: FeedItem) {
        guard Self.shouldNotify(item) else { return }
        center.add(UNNotificationRequest(identifier: "verdict-\(item.id)",
                                         content: Self.content(for: item), trigger: nil))
    }
}
