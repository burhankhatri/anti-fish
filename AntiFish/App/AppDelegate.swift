import AppKit
import UserNotifications

extension Notification.Name {
    static let antifishOpenVerdict = Notification.Name("antifish.openVerdict")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let pk = response.notification.request.content.userInfo["messagePK"] as? Int64 else { return }
        await MainActor.run {
            NSApp.activate()
            NotificationCenter.default.post(name: .antifishOpenVerdict, object: nil,
                                            userInfo: ["messagePK": pk])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
