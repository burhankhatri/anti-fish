import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.phase == .ready {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .task { await model.start(); await model.loadClaimCandidates() }
        .onReceive(NotificationCenter.default.publisher(for: .antifishOpenVerdict)) { note in
            if let pk = note.userInfo?["messagePK"] as? Int64 { model.selectedItemID = pk }
        }
    }
}
