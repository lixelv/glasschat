#if DEBUG
import Foundation

extension SelfTests {
    static func smoothing() {
        expect(abs(Smoothing.step(current: 0, target: 1, dt: 0.4, time: 0.4) - 0.632) < 0.01, "one time constant: about 63 %")
        let big = Smoothing.step(current: 0, target: 1, dt: 10, time: 0.4)
        expect(big <= 1 && big > 0.99, "a long frame reaches the target without overshooting")
        expect(Smoothing.step(current: 1, target: 0, dt: 0.1, time: 0.4) < 1 && Smoothing.step(current: 1, target: 0, dt: 0.1, time: 0.4) > 0, "it moves the other way too")
        let ceiling = Waveform.minimumHeight + 0.6 * (22 - Waveform.minimumHeight) + 0.001
        let wave = (0..<200).map { Waveform.height($0 % 6, of: 6, mode: .wave, level: 0, time: Double($0) * 0.05, maxHeight: 22) }
        expect(wave.allSatisfy { $0 <= ceiling }, "the thinking wave stays low (60 %)")
    }
}
#endif
