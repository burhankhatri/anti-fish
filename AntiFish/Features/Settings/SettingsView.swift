import AntiFishCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var notificationsAuthorized = false

    var body: some View {
        Form {
            Section("Calibration") {
                if let c = model.calibration {
                    LabeledContent("Status", value: c.thresholds.calibrated
                                   ? "Learned from \(c.contactCount) of your contacts"
                                   : "Starting values — needs five or more enrolled contacts")
                    LabeledContent("Match above", value: number(c.thresholds.match))
                    LabeledContent("Mismatch below", value: number(c.thresholds.reject))
                    LabeledContent("Your contacts score", value: number(c.genuineMedian))
                    LabeledContent("Everyone else scores", value: number(c.impostorMedian))
                    LabeledContent("Last calibrated",
                                   value: c.calibratedAt.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Not calibrated yet.").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Recalibrate") { model.recalibrate() }
                        .accessibilityIdentifier("settings.recalibrate")
                    Button(model.needsRebuild ? "Rebuild fingerprints (recommended)" : "Rebuild fingerprints") {
                        Task { await model.rebuildFingerprints() }
                    }
                    .accessibilityIdentifier("settings.rebuild")
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LoginItem.set(enabled: on) }
                LabeledContent("Notifications", value: notificationsAuthorized
                               ? "On — only for suspected impersonations"
                               : "Off — enable AntiFish in System Settings → Notifications")
            }

            Section("Privacy") {
                Text("Everything runs on this Mac. AntiFish reads WhatsApp's local voice notes, keeps fingerprints in your Application Support folder, and never uses the network.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .accessibilityIdentifier("settings.form")
        .task {
            await model.notifier.refreshAuthorization()
            notificationsAuthorized = model.notifier.isAuthorized
        }
    }

    private func number(_ v: Float) -> String {
        v.formatted(.number.precision(.fractionLength(2)))
    }
}
