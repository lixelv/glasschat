#if DEBUG
import Foundation

extension SelfTests {
    static func waveform() {
        let still = (0..<6).map { Waveform.height($0, of: 6, mode: .input, level: 0, time: 1.3, maxHeight: 22) }
        expect(still.allSatisfy { $0 == Waveform.minimumHeight }, "silence: flat bars (nothing left from the last sound)")
        let idle = (0..<6).map { Waveform.height($0, of: 6, mode: .idle, level: 0.9, time: 1.3, maxHeight: 22) }
        expect(idle.allSatisfy { $0 == Waveform.minimumHeight }, "idle: flat whatever the level")
        let loud = (0..<6).map { Waveform.height($0, of: 6, mode: .input, level: 1, time: 0, maxHeight: 22) }
        expect(loud[2] > loud[0] && loud[3] > loud[5] && loud.allSatisfy { $0 <= 22 }, "loud: tallest in the middle, within the notch")
        let a = Waveform.height(1, of: 6, mode: .wave, level: 0, time: 0, maxHeight: 22)
        let b = Waveform.height(1, of: 6, mode: .wave, level: 0, time: 0.25, maxHeight: 22)
        expect(a != b, "thinking: the wave flows on its own")
    }
}
#endif
