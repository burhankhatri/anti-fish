import AppKit
import SwiftUI

/// A checklist that updates itself, never a modal that blocks. The permission row flips on its own
/// within a second of the grant, so there is no "I've done it" button to press.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var notificationsOn = true
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 24) {
            BrandMark(size: 92)
            VStack(spacing: 6) {
                Text("AntiFish")
                    .font(AppType.heading)
                    .foregroundStyle(Color.onSurface)
                Text(tagline)
                    .font(AppType.bodySm)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Group {
                switch model.phase {
                case .needsWhatsApp: needsWhatsApp
                case .needsFullDiskAccess: needsFullDiskAccess
                case .setupChoices: setupChoices
                case .enrolling(let done, let total): enrolling(done: done, total: total)
                default: ProgressView()
                }
            }
            .frame(maxWidth: 440)
        }
        .padding(Spacing.xxl)
        .frame(minWidth: 600, minHeight: 540)
        .background(Color.background)
    }

    private var tagline: String {
        "Tells you when a voice note doesn't sound like the person it claims to be from. Everything stays on this Mac."
    }

    private var needsWhatsApp: some View {
        StepCard(state: .waiting, title: "WhatsApp Desktop not found",
                 identifier: "onboarding.needsWhatsApp",
                 detail: "Install WhatsApp for Mac and link it to your phone. AntiFish reads the voice notes WhatsApp already stores here.") {
            Button("Check again") { Task { await model.start() } }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.checkAgain")
        }
    }

    private var needsFullDiskAccess: some View {
        StepCard(state: .waiting, title: "Allow Full Disk Access",
                 identifier: "onboarding.needsFDA",
                 detail: "macOS keeps WhatsApp's files private to WhatsApp. Turn on AntiFish under System Settings → Privacy & Security → Full Disk Access. This step completes itself once you do.") {
            HStack {
                Button("Open System Settings") { PermissionProbe.openFullDiskAccessSettings() }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Relaunch AntiFish") { relaunch() }
                    .buttonStyle(.borderless)
                    .help("macOS sometimes needs a relaunch before the grant takes effect")
            }
        }
        .task {
            await PermissionProbe.waitUntilReadable(model.locator)
            await model.start()
        }
    }

    private var setupChoices: some View {
        StepCard(state: .ready, title: "Two choices", identifier: "onboarding.setup",
                 detail: "AntiFish sits in the menu bar. A verified note never interrupts you; only a suspected impersonation does.") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Notify me when a voice note looks like an impersonation", isOn: $notificationsOn)
                Toggle("Launch AntiFish at login", isOn: $launchAtLogin)
                HStack {
                    Spacer()
                    Button("Continue") {
                        Task {
                            if notificationsOn { _ = await model.notifier.requestAuthorization() }
                            LoginItem.set(enabled: launchAtLogin)
                            await model.completeSetup()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.continue")
                }
            }
        }
    }

    private func enrolling(done: Int, total: Int) -> some View {
        StepCard(state: .working, title: "Learning the voices you know",
                 identifier: "onboarding.enrolling",
                 detail: "Listening to the voice notes already on this Mac. This happens once and takes a few minutes.") {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: total > 0 ? Double(done) / Double(total) : nil)
                Text(total > 0 ? "\(done) of \(total) notes" : "Preparing…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

struct StepCard<Actions: View>: View {
    enum State { case waiting, working, ready }

    let state: State
    let title: String
    let identifier: String
    let detail: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                glyph
                Text(title)
                    .font(AppType.title)
                    .foregroundStyle(Color.onSurface)
                    .accessibilityIdentifier(identifier)
            }
            Text(detail)
                .font(AppType.bodySm)
                .foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceContainerLowest,
                    in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .waiting:
            Image(systemName: "circle.dashed").foregroundStyle(Color.outlineVariant)
        case .working:
            ProgressView().controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.successGreen)
        }
    }
}

