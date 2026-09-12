import AntiFishCore
import SwiftUI

/// Places a similarity score against the one line that decides the answer.
/// Only the side the score falls on is coloured; the other stays neutral.
enum ScoreMeter {
    enum Band: Equatable { case below, above }

    static func band(for score: Float, thresholds t: Thresholds) -> Band {
        score >= t.decision ? .above : .below
    }

    /// Maps a cosine score in -1...1 onto 0...1 across the bar.
    static func position(of score: Float, thresholds: Thresholds) -> Double {
        Double(min(max(score, -1), 1) + 1) / 2
    }
}

struct ScoreMeterView: View {
    let score: Float
    let thresholds: Thresholds
    var errorRate: Float = 0

    private var band: ScoreMeter.Band { ScoreMeter.band(for: score, thresholds: thresholds) }
    private var lineAt: Double { ScoreMeter.position(of: thresholds.decision, thresholds: thresholds) }
    private var scoreAt: Double { ScoreMeter.position(of: score, thresholds: thresholds) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(score, format: .number.precision(.fractionLength(2)))
                    .font(AppType.headingSm)
                    .foregroundStyle(Color.onSurface)
                    .contentTransition(.numericText())
                Text(band == .above ? "above the line" : "below the line")
                    .font(AppType.caption)
                    .foregroundStyle(band == .above ? Color.onSuccessContainer : Color.onErrorContainer)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 3)
                    .background(band == .above ? Color.successContainer : Color.errorContainer,
                                in: Capsule())
                Spacer()
            }

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(band == .below ? Color.errorContainer : Color.surfaceContainerHigh)
                        .frame(width: max(0, w * lineAt), height: 8)
                    Capsule()
                        .fill(band == .above ? Color.successContainer : Color.surfaceContainerHigh)
                        .frame(width: max(0, w * (1 - lineAt)), height: 8)
                        .offset(x: w * lineAt)
                    Rectangle()
                        .fill(Color.onSurfaceVariant)
                        .frame(width: 1.5, height: 16)
                        .offset(x: w * lineAt)
                    Circle()
                        .fill(Color.onSurface)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(Color.surfaceContainerLowest, lineWidth: 3))
                        .offset(x: w * scoreAt - 6.5)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: scoreAt)
                }
                .frame(height: 16)
            }
            .frame(height: 16)

            Text(footnote)
                .font(AppType.captionSm)
                .foregroundStyle(Color.outlineColor)
        }
    }

    private var footnote: String {
        let line = thresholds.decision.formatted(.number.precision(.fractionLength(2)))
        guard thresholds.calibrated else { return "The line sits at \(line), a starting value." }
        guard errorRate > 0 else { return "The line sits at \(line), learned from your own contacts." }
        let percent = Int((errorRate * 100).rounded())
        return "The line sits at \(line), learned from your contacts. It is wrong about \(percent)% of the time."
    }
}
