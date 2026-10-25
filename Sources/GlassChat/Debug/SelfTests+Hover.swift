#if DEBUG
import Foundation

extension SelfTests {
    static func hover() {
        expect(!HoverTalk.shouldStart(hovered: 0.2, delay: 0.3, enabled: true, expanded: false, busy: false), "passing over the notch does not start")
        expect(HoverTalk.shouldStart(hovered: 0.3, delay: 0.3, enabled: true, expanded: false, busy: false), "resting on it starts")
        expect(!HoverTalk.shouldStart(hovered: 1, delay: 0.3, enabled: false, expanded: false, busy: false), "switched off")
        expect(!HoverTalk.shouldStart(hovered: 1, delay: 0.3, enabled: true, expanded: true, busy: false), "the open notch has its own listening")
        expect(!HoverTalk.shouldStart(hovered: 1, delay: 0.3, enabled: true, expanded: false, busy: true), "not while answering")
        expect(HoverTalk.outcome(voiced: 0.8) == .open, "something said: the notch opens")
        expect(HoverTalk.outcome(voiced: 0.2) == .discard, "nothing said: it stays folded")
        // Opening the notch while hover-recording turns it into ordinary listening (the pointer may leave).
        expect(HoverTalk.switchesToListening(hoverTalking: true, expanded: true), "click during hover talk: ordinary listening")
        expect(!HoverTalk.switchesToListening(hoverTalking: false, expanded: true), "nothing to switch")
        // The flowing wave is only for thinking about the answer.
        typealias A = AssistantController
        expect(A.waveMode(for: .answering, speaking: false) == .wave, "thinking: wave")
        expect(A.waveMode(for: .transcribing, speaking: false) == .idle, "transcribing: still")
        expect(A.waveMode(for: .listening(followUp: false), speaking: false) == .input, "listening: the voice")
        expect(A.waveMode(for: .idle, speaking: true) == .output && A.waveMode(for: .idle, speaking: false) == .idle, "speaking / idle")
    }
}
#endif
