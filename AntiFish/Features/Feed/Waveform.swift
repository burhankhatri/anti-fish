import SwiftUI

/// The waveform is the scrubber: played bars solid, unplayed faint, click to seek.
/// No dancing equaliser — it would undercut the tone of the app.
struct Waveform: View {
    let levels: [Float]
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    let played = Double(index) / Double(max(1, levels.count - 1)) <= progress
                    RoundedRectangle(cornerRadius: 1)
                        .fill(played ? Color.primaryContainer : Color.surfaceDim)
                        .frame(width: 2, height: max(4, CGFloat(level) * 28))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                onSeek(min(1, max(0, value.location.x / geo.size.width)))
            })
        }
        .frame(height: 32)
    }
}
