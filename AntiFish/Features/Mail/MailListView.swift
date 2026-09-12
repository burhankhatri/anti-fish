import AntiFishCore
import SwiftUI

struct MailListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedMailID) {
            ForEach(model.mailMessages) { message in
                MailRowView(message: message).tag(message.id)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceContainerLow)
        .accessibilityIdentifier("mail.list")
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .overlay {
            if model.mailMessages.isEmpty { empty }
        }
        .task { model.loadCachedMail() }
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            if let scan = model.mailScan {
                Text("\(scan.scanned) checked")
                    .font(AppType.captionSm)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            Spacer()
            if model.isScanningMail {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await model.scanMail() }
                } label: {
                    Label("Check mail", systemImage: "arrow.clockwise")
                        .font(AppType.captionSm)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("mail.scan")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.surfaceContainerLow)
    }

    private var empty: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "envelope.open")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.outlineVariant)
            Text(model.mailIsAvailable ? "No mail checked yet" : "No mail on this Mac")
                .font(AppType.title)
                .foregroundStyle(Color.onSurface)
            Text(model.mailIsAvailable
                 ? "Check mail reads what Mail.app has already downloaded."
                 : "Open Mail.app and let it download your messages first.")
                .font(AppType.bodySm)
                .foregroundStyle(Color.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            if model.mailIsAvailable, !model.isScanningMail {
                Button("Check mail") { Task { await model.scanMail() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.primaryContainer)
            }
        }
        .padding(Spacing.lg)
    }
}

struct MailRowView: View {
    let message: MailMessage

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle().fill(tierContainer).frame(width: 34, height: 34)
                Image(systemName: tierSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tierForeground)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(message.displayName)
                        .font(AppType.bodySmMedium)
                        .foregroundStyle(Color.onSurface)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let date = message.date {
                        Text(ChatRowView.stamp(date))
                            .font(AppType.captionSm)
                            .foregroundStyle(Color.outlineColor)
                    }
                }
                Text(message.subject)
                    .font(AppType.caption)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(message.tier.title)
                        .font(AppType.captionSm)
                        .foregroundStyle(tierForeground)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tierContainer, in: Capsule())
                    if message.hasImages {
                        Image(systemName: "photo")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.outlineColor)
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("mail.row.\(message.id)")
    }

    private var tierSymbol: String {
        switch message.tier {
        case .danger: "exclamationmark.triangle.fill"
        case .caution: "eye.fill"
        case .safe: "checkmark"
        case .unknown: "questionmark"
        }
    }

    private var tierForeground: Color {
        switch message.tier {
        case .danger: .onErrorContainer
        case .caution: .onCautionContainer
        case .safe: .onSuccessContainer
        case .unknown: .onSurfaceVariant
        }
    }

    private var tierContainer: Color {
        switch message.tier {
        case .danger: .errorContainer
        case .caution: .cautionContainer
        case .safe: .successContainer
        case .unknown: .surfaceContainerHigh
        }
    }
}
