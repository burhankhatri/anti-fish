import SwiftUI

@main
struct AntiFishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("AntiFish", id: "main") {
            RootView().environment(model)
        }
        .defaultSize(width: 900, height: 620)

        Window("Contacts", id: "contacts") {
            ContactsView().environment(model)
        }
        .defaultSize(width: 620, height: 520)

        Settings {
            SettingsView().environment(model)
        }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: model.lastNeedingAttention == nil
                  ? "waveform.badge.magnifyingglass"
                  : "waveform.badge.exclamationmark")
        }
        .menuBarExtraStyle(.window)
    }
}
