import SwiftUI

/// White bars beside the notch: the microphone or the voice, a wave while thinking, flat when idle.
struct Waveform: View {
    enum Mode: Equatable { case idle, input, wave, output }

    let mode: Mode
    let level: Double
    var bars = 6
    var maxHeight: CGFloat = 22

    @State private var history: [Double] = []

    var body: some View {
        TimelineView(.animation(paused: mode != .wave)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 3, height: height(i, t: t))
                }
            }
            .frame(height: maxHeight)
        }
        .animation(.easeOut(duration: 0.08), value: history)
        .onChange(of: level) { _, value in
            history = Array((history + [value]).suffix(bars))
        }
        .accessibilityHidden(true)
    }

    private func height(_ i: Int, t: Double) -> CGFloat {
        let minimum: CGFloat = 4
        switch mode {
        case .idle:
            return minimum
        case .wave:
            return minimum + (maxHeight - minimum) * CGFloat(0.5 + 0.5 * sin(t * 6 + Double(i) * 0.8))
        case .input, .output:
            // Newest in the middle, older ones toward the sides.
            let order = abs(Double(i) - Double(bars - 1) / 2)
            let index = history.count - 1 - Int(order.rounded())
            let value = index >= 0 && index < history.count ? history[index] : 0
            return minimum + (maxHeight - minimum) * CGFloat(value)
        }
    }
}
