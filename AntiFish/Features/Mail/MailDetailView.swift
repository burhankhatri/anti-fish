import AntiFishCore
import SwiftUI

/// One message and why PhishGuard reached its verdict. Written for someone who has never heard of
/// DMARC: the headline is a sentence, each reason is a sentence, and the code is a footnote.
struct MailDetailView: View {
    @Environment(AppModel.self) private var model
    let message: MailMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                verdictCard
                senderCard
                if !message.findings.isEmpty { reasons }
                if !message.mitigating.isEmpty { reassurances }
                if !message.attachmentNames.isEmpty { attachments }
                if !message.snippet.isEmpty { preview }
            }
            .padding(Spacing.lg)
        }
        .background(Color.background)
        .accessibilityIdentifier("mail.detail")
    }

    private var verdictCard: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(foreground)
            VStack(alignment: .leading, spacing: 5) {
                Text(message.tier.title)
                    .font(AppType.headingSm)
                    .foregroundStyle(foreground)
                Text(message.headline)
                    .font(AppType.bodySm)
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(container, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }

    private var senderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.subject)
                .font(AppType.subheading)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(message.displayName).font(AppType.bodySmMedium)
                Text(message.fromAddress).font(AppType.caption).foregroundStyle(Color.onSurfaceVariant)
            }
            if let date = message.date {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(AppType.caption)
                    .foregroundStyle(Color.outlineColor)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceContainerLowest,
                    in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
    }

    private var reasons: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Why").font(AppType.bodyMedium).foregroundStyle(Color.onSurface)
            ForEach(message.findings) { finding in
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.errorRed)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(finding.explanation)
                            .font(AppType.bodySm)
                            .foregroundStyle(Color.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                        if !finding.detail.isEmpty {
                            Text(finding.detail)
                                .font(AppType.captionSm)
                                .foregroundStyle(Color.outlineColor)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var reassurances: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("In its favour").font(AppType.bodyMedium).foregroundStyle(Color.onSurface)
            ForEach(message.mitigating) { finding in
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.successGreen)
                        .padding(.top, 2)
                    Text(finding.explanation)
                        .font(AppType.bodySm)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
    }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Attached").font(AppType.bodyMedium).foregroundStyle(Color.onSurface)
            ForEach(message.attachmentNames, id: \.self) { name in
                HStack(spacing: Spacing.xs) {
                    Image(systemName: isImage(name) ? "photo" : "doc")
                        .foregroundStyle(Color.onSurfaceVariant)
                    Text(name).font(AppType.bodySm).foregroundStyle(Color.onSurface).lineLimit(1)
                    Spacer()
                    if isImage(name) {
                        Text(model.imageCheckAvailable ? "can be checked" : "checking is off")
                            .font(AppType.captionSm)
                            .foregroundStyle(Color.outlineColor)
                    }
                }
                .padding(.vertical, 3)
            }
            if message.hasImages, !model.imageCheckAvailable {
                Text(model.imageCheckReason)
                    .font(AppType.captionSm)
                    .foregroundStyle(Color.outlineColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceContainerLowest,
                    in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("The message").font(AppType.bodyMedium).foregroundStyle(Color.onSurface)
            Text(message.snippet)
                .font(AppType.bodySm)
                .foregroundStyle(Color.onSurfaceVariant)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func isImage(_ name: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(
            (name as NSString).pathExtension.lowercased())
    }

    private var symbol: String {
        switch message.tier {
        case .danger: "exclamationmark.triangle.fill"
        case .caution: "eye.fill"
        case .safe: "checkmark.seal.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var foreground: Color {
        switch message.tier {
        case .danger: .onErrorContainer
        case .caution: .onCautionContainer
        case .safe: .onSuccessContainer
        case .unknown: .onSurfaceVariant
        }
    }

    private var container: Color {
        switch message.tier {
        case .danger: .errorContainer
        case .caution: .cautionContainer
        case .safe: .successContainer
        case .unknown: .surfaceContainerHigh
        }
    }
}
