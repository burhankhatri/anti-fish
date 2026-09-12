import AntiFishCore
import SwiftUI

/// Places a similarity score against the two learned thresholds.
///
/// Only the band the score falls in is coloured; the rest stay grey. A full rainbow always looks
/// alarming, a mostly-grey bar does not. Thresholds are spelled out underneath so the number never
/// reads as a black box.
enum ScoreMeter {
    enum Band: Equatable {
        case mismatch, inconclusive, match
    }

    static func band(for score: Float, thresholds t: Thresholds) -> Band {
        if score <= t.reject { return .mismatch }
        if score >= t.match { return .match }
        return .inconclusive
    }

    /// Maps a cosine score in -1...1 onto 0...1 across the bar.
    static func position(of score: Float, thresholds: Thresholds) -> Double {
        Double(min(max(score, -1), 1) + 1) / 2
    }
}

struct ScoreMeterView: View {
    let score: Float
    let thresholds: Thresholds

    private var band: ScoreMeter.Band { ScoreMeter.band(for: score, thresholds: thresholds) }
    private var rejectAt: Double { ScoreMeter.position(of: thresholds.reject, thresholds: thresholds) }
    private var matchAt: Double { ScoreMeter.position(of: thresholds.match, thresholds: thresholds) }
    private var scoreAt: Double { ScoreMeter.position(of: score, thresholds: thresholds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(score, format: .number.precision(.fractionLength(2)))
                    .font(.title.monospacedDigit())
                    .contentTransition(.numericText())
                Text(bandLabel)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(bandTint.opacity(0.14), in: Capsule())
                Spacer()
            }

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    segment(width: w * rejectAt, active: band == .mismatch, tint: .orange)
                        .offset(x: 0)
                    segment(width: w * (matchAt - rejectAt), active: band == .inconclusive, tint: .gray)
                        .offset(x: w * rejectAt)
                    segment(width: w * (1 - matchAt), active: band == .match, tint: .green)
                        .offset(x: w * matchAt)

                    tick.offset(x: w * rejectAt)
                    tick.offset(x: w * matchAt)

                    Circle()
                        .fill(.primary)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 3))
                        .offset(x: w * scoreAt - 6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: scoreAt)
                }
                .frame(height: 14)
            }
            .frame(height: 14)

            HStack {
                Text("mismatch below \(thresholds.reject, format: .number.precision(.fractionLength(2)))")
                Spacer()
                Text(thresholds.calibrated ? "learned from your contacts" : "starting values")
                Spacer()
                Text("match above \(thresholds.match, format: .number.precision(.fractionLength(2)))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }

    private func segment(width: CGFloat, active: Bool, tint: Color) -> some View {
        Capsule()
            .fill(active ? AnyShapeStyle(tint.opacity(0.8)) : AnyShapeStyle(.quaternary))
            .frame(width: max(0, width), height: 8)
    }

    private var tick: some View {
        Rectangle()
            .fill(.secondary)
            .frame(width: 1, height: 14)
    }

    private var bandLabel: String {
        switch band {
        case .mismatch: "Does not match"
        case .inconclusive: "Inconclusive"
        case .match: "Matches"
        }
    }

    private var bandTint: Color {
        switch band {
        case .mismatch: .orange
        case .inconclusive: .gray
        case .match: .green
        }
    }
}
