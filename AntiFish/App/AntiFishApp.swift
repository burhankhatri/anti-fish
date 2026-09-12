import SwiftUI

@main
struct AntiFishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("AntiFish", id: "main") {
            RootView()
                .environment(model)
                .preferredColorScheme(.light)
                .tint(Color.primaryContainer)
        }
        .defaultSize(width: 1180, height: 820)
        .defaultPosition(.topLeading)

        Window("Flagged voice notes", id: "flagged") {
            FlaggedView()
                .environment(model)
                .preferredColorScheme(.light)
                .tint(Color.primaryContainer)
        }
        .defaultSize(width: 720, height: 520)

        Window("Voices", id: "contacts") {
            ContactsView()
                .environment(model)
                .preferredColorScheme(.light)
                .tint(Color.primaryContainer)
        }
        .defaultSize(width: 620, height: 520)

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.light)
                .tint(Color.primaryContainer)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
                .preferredColorScheme(.light)
                .tint(Color.primaryContainer)
        } label: {
            if let mark = BrandMark.image {
                Image(nsImage: mark).resizable().scaledToFit()
            } else {
                Image(systemName: model.lastNeedingAttention == nil
                      ? "waveform.badge.magnifyingglass"
                      : "waveform.badge.exclamationmark")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
