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
    }
}
#endif
