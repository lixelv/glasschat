import SwiftUI

/// White bars beside the notch: the microphone or the voice, a slow low wave while thinking, flat otherwise.
/// Drawn from the current level every frame (nothing of a past sound stays) and glide between states.
struct Waveform: View {
    enum Mode: Equatable { case idle, input, wave, output }

    let mode: Mode
    let level: Double
    var bars = 6
    var maxHeight: CGFloat = 22

    static let minimumHeight: CGFloat = 4

    @State private var smoothed = SmoothedValues()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let targets = (0..<bars).map { Double(Self.height($0, of: bars, mode: mode, level: level, time: t, maxHeight: maxHeight)) }
            let heights = smoothed.advance(to: targets, at: t, timeConstant: 0.08)
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 3, height: CGFloat(heights[i]))
                }
            }
            .frame(height: maxHeight)
        }
        .accessibilityHidden(true)
    }

    /// The height of bar `i`: the level shaped tallest in the middle with a little flicker; the wave on its own.
    static func height(_ i: Int, of bars: Int, mode: Mode, level: Double, time t: Double, maxHeight: CGFloat) -> CGFloat {
        let range = maxHeight - minimumHeight
        switch mode {
        case .idle:
            return minimumHeight
        case .wave:
            // Slow and low: thinking, not working hard.
            return minimumHeight + range * CGFloat(0.3 + 0.3 * sin(t * 3 + Double(i) * 0.8))
        case .input, .output:
            let middle = Double(bars - 1) / 2
            let shape = 1 - 0.5 * abs(Double(i) - middle) / max(middle, 1)
            let flicker = 0.8 + 0.2 * sin(t * 9 + Double(i) * 1.7)
            let value = min(max(level, 0), 1) * shape * flicker
            return minimumHeight + range * CGFloat(value)
        }
    }
}
