import SwiftUI

/// White bars beside the notch: the microphone or the voice, a flowing wave while thinking, flat otherwise.
/// Drawn from the current level every frame, so nothing of a past sound stays on screen.
struct Waveform: View {
    enum Mode: Equatable { case idle, input, wave, output }

    let mode: Mode
    let level: Double
    var bars = 6
    var maxHeight: CGFloat = 22

    static let minimumHeight: CGFloat = 4

    var body: some View {
        TimelineView(.animation(paused: mode == .idle)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 3, height: Self.height(i, of: bars, mode: mode, level: level, time: t, maxHeight: maxHeight))
                }
            }
            .frame(height: maxHeight)
        }
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }

    /// The height of bar `i`: the level shaped tallest in the middle with a little flicker; the wave on its own.
    static func height(_ i: Int, of bars: Int, mode: Mode, level: Double, time t: Double, maxHeight: CGFloat) -> CGFloat {
        let range = maxHeight - minimumHeight
        switch mode {
        case .idle:
            return minimumHeight
        case .wave:
            return minimumHeight + range * CGFloat(0.5 + 0.5 * sin(t * 6 + Double(i) * 0.8))
        case .input, .output:
            let middle = Double(bars - 1) / 2
            let shape = 1 - 0.5 * abs(Double(i) - middle) / max(middle, 1)
            let flicker = 0.8 + 0.2 * sin(t * 9 + Double(i) * 1.7)
            let value = min(max(level, 0), 1) * shape * flicker
            return minimumHeight + range * CGFloat(value)
        }
    }
}
