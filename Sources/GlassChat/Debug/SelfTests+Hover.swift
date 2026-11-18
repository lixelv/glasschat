#if DEBUG
import Foundation

extension SelfTests {
    static func hover() {
        // The flowing wave is only for thinking about the answer.
        typealias A = AssistantController
        expect(A.waveMode(for: .answering, speaking: false) == .wave, "thinking: wave")
        expect(A.waveMode(for: .transcribing, speaking: false) == .idle, "transcribing: still")
        expect(A.waveMode(for: .listening(followUp: false), speaking: false) == .input, "listening: the voice")
        expect(A.waveMode(for: .idle, speaking: true) == .output && A.waveMode(for: .idle, speaking: false) == .idle, "speaking / idle")
    }
}
#endif
