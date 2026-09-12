import AntiFishCore
import SwiftUI

/// The question the app exists to answer: someone you do not know sends a voice note, and says
/// they are someone you do. Pick that person and the app tests the claim.
struct ClaimPicker: View {
    @Environment(AppModel.self) private var model
    let item: ThreadItem

    private var result: Verdict? { model.claimResults[item.id] }
    private var isChecking: Bool { model.claimInFlight == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let result {
                answer(result)
            } else {
                prompt
            }
        }
        .padding(.top, 2)
    }

    private var prompt: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 12))
                .foregroundStyle(Color.onSurfaceVariant)
            Text("Say they're")
                .font(AppType.caption)
                .foregroundStyle(Color.onSurfaceVariant)
            if isChecking {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    ForEach(model.claimCandidates) { candidate in
                        Button {
                            Task { await model.checkClaim(item, claiming: candidate.jid) }
                        } label: {
                            Text("\(candidate.name)  ·  \(candidate.noteCount) notes")
                        }
                    }
                } label: {
                    Text("choose someone")
                        .font(AppType.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 130)
                .accessibilityIdentifier("claim.picker.\(item.id)")
            }
            Spacer()
        }
    }

    private func answer(_ verdict: Verdict) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: VerdictStyle.symbol(verdict.kind))
                    .font(.system(size: 12, weight: .semibold))
                Text(headline(verdict))
                    .font(AppType.bodySmMedium)
                Spacer()
                Button {
                    model.clearClaim(item)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.outlineColor)
            }
            .foregroundStyle(VerdictStyle.foreground(verdict.kind))

            Text(verdict.explanation)
                .font(AppType.caption)
                .foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerdictStyle.container(verdict.kind),
                    in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityIdentifier("claim.answer.\(item.id)")
    }

    /// Short enough to read at a glance, which is the whole point for someone who does not want
    /// to read a paragraph before deciding whether to trust a message.
    private func headline(_ verdict: Verdict) -> String {
        let who = verdict.comparedJID.map { model.name(for: $0) } ?? "them"
        switch verdict.kind {
        case .impersonationSuspected, .takeoverSuspected: return "Not \(who)"
        case .verified: return "This is \(who)"
        case .matchesUnsavedNumber: return "Sounds like \(who)"
        case .unknownVoice: return "Not a voice you know"
        case .unverifiable, .unclear: return "Can't tell"
        }
    }
}
