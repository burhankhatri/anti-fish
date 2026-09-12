import AntiFishCore
import AppKit

enum PermissionProbe {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    /// Full Disk Access has no API to ask, so the only honest test is trying to read. Polls until
    /// the grant lands, which is usually within a second of the user flipping the switch.
    static func waitUntilReadable(_ locator: ContainerLocator) async {
        while !Task.isCancelled, !locator.hasFullDiskAccess {
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
