#if DEBUG
import AppKit
import Carbon.HIToolbox

extension SelfTests {
    static func pushToTalk() {
        typealias E = PushToTalk.Edge
        let chord = Shortcut.standard                                   // ⌥⌘
        let cmdK = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: [.command], key: "K")
        let f5 = Shortcut(keyCode: UInt32(kVK_F5), modifiers: [], key: "F5")
        let other = UInt32(kVK_ANSI_J)

        // PTT-7: a modifier-only chord.
        var t = PushToTalk.Tracker(chord)
        expect(!t.isHeld, "PTT-7: nothing held at first")
        expect(t.flagsChanged([.option]) == nil, "PTT-7: half the chord is nothing")
        expect(t.flagsChanged([.option, .command]) == .press, "PTT-7: exactly the chord presses")
        expect(t.isHeld, "PTT-7: held after the press")
        expect(t.flagsChanged([.option, .command]) == nil, "PTT-7: the same flags again are nothing")
        expect(t.flagsChanged([.command]) == .release, "PTT-7: letting one go releases")
        expect(!t.isHeld, "PTT-7: not held after the release")
        expect(t.flagsChanged([]) == nil, "PTT-7: letting the rest go adds no event")

        // PTT-7: the other order, and flags that are not modifiers are ignored.
        t = PushToTalk.Tracker(chord)
        expect(t.flagsChanged([.command]) == nil && t.flagsChanged([.command, .option, .capsLock]) == .press, "PTT-7: either order, caps lock ignored")
        expect(t.flagsChanged([.command, .option]) == nil, "PTT-7: caps lock going off changes nothing")
        expect(t.flagsChanged([]) == .release, "PTT-7: both up releases")

        // PTT-7: an extra modifier cancels, and only a full let-go re-arms.
        t = PushToTalk.Tracker(chord)
        var edges: [E] = []
        func feed(_ edge: E?) { if let edge { edges.append(edge) } }
        feed(t.flagsChanged([.option, .command]))
        feed(t.flagsChanged([.option, .command, .shift]))
        feed(t.flagsChanged([.option, .command]))
        feed(t.flagsChanged([.command]))
        feed(t.flagsChanged([]))
        expect(edges == [.press, .cancel], "PTT-7: an extra modifier: one press, one cancel, no release")
        expect(!t.isHeld, "PTT-7: not held after a cancel and let-go")
        expect(t.flagsChanged([.option, .command]) == .press, "PTT-7: pressed again after everything was let go")
        expect(t.flagsChanged([]) == .release, "PTT-7: and released normally")

        // PTT-7: a wrong extra modifier before the chord never presses.
        t = PushToTalk.Tracker(chord)
        expect(t.flagsChanged([.shift]) == nil && t.flagsChanged([.shift, .option]) == nil && t.flagsChanged([.shift, .option, .command]) == nil,
               "PTT-7: a superset of the chord is not the chord")
        expect(t.flagsChanged([]) == nil, "PTT-7: and lets go quietly")

        // PTT-7: any key while the chord is held cancels (⌥⌘Esc).
        t = PushToTalk.Tracker(chord)
        edges = []
        feed(t.flagsChanged([.option, .command]))
        feed(t.keyDown(UInt32(kVK_Escape), isRepeat: false))
        feed(t.keyUp(UInt32(kVK_Escape)))
        feed(t.flagsChanged([]))
        expect(edges == [.press, .cancel], "PTT-7: another key cancels instead of releasing")
        expect(t.keyDown(other, isRepeat: false) == nil, "PTT-7: a key with nothing held is nothing")

        // PTT-7: a key chord (⌘K).
        t = PushToTalk.Tracker(cmdK)
        expect(t.flagsChanged([.command]) == nil, "PTT-7: the modifier alone is not the key chord")
        expect(t.keyDown(UInt32(kVK_ANSI_K), isRepeat: false) == .press, "PTT-7: the key with its modifiers presses")
        expect(t.isHeld, "PTT-7: key chord held")
        expect(t.keyDown(UInt32(kVK_ANSI_K), isRepeat: true) == nil, "PTT-7: auto-repeat is not a new press")
        expect(t.keyUp(UInt32(kVK_ANSI_K)) == .release, "PTT-7: the key up releases")
        expect(!t.isHeld, "PTT-7: key chord let go")
        expect(t.keyDown(UInt32(kVK_ANSI_K), isRepeat: false) == .press && t.keyUp(UInt32(kVK_ANSI_K)) == .release, "PTT-7: pressing again works")
        expect(t.flagsChanged([]) == nil, "PTT-7: modifiers up afterwards add nothing")

        t = PushToTalk.Tracker(cmdK)
        _ = t.flagsChanged([.command])
        expect(t.keyDown(UInt32(kVK_ANSI_K), isRepeat: false) == .press, "PTT-7: pressed")
        expect(t.flagsChanged([]) == .release, "PTT-7: modifiers lost while the key is down releases")
        expect(t.keyUp(UInt32(kVK_ANSI_K)) == nil, "PTT-7: the key up after that adds nothing")

        t = PushToTalk.Tracker(cmdK)
        _ = t.flagsChanged([.command, .shift])
        expect(t.keyDown(UInt32(kVK_ANSI_K), isRepeat: false) == nil, "PTT-7: the key with an extra modifier is not the chord")
        t = PushToTalk.Tracker(cmdK)
        expect(t.keyDown(UInt32(kVK_ANSI_K), isRepeat: false) == nil, "PTT-7: the key with no modifiers is not the chord")
        expect(t.flagsChanged([.command]) == nil, "PTT-7: modifiers coming after the key do not press")

        t = PushToTalk.Tracker(cmdK)
        edges = []
        _ = t.flagsChanged([.command])
        feed(t.keyDown(UInt32(kVK_ANSI_K), isRepeat: false))
        feed(t.keyDown(other, isRepeat: false))
        feed(t.keyUp(other))
        feed(t.keyUp(UInt32(kVK_ANSI_K)))
        feed(t.flagsChanged([]))
        expect(edges == [.press, .cancel], "PTT-7: another key while the key chord is held cancels, once")

        // PTT-7: a function key alone.
        t = PushToTalk.Tracker(f5)
        expect(t.keyDown(UInt32(kVK_F5), isRepeat: false) == .press && t.keyUp(UInt32(kVK_F5)) == .release, "PTT-7: F5 alone presses and releases")
        expect(t.flagsChanged([.shift]) == nil && t.keyDown(UInt32(kVK_F5), isRepeat: false) == nil, "PTT-7: F5 with a modifier is not F5 alone")

        // PTT-3: what a release does.
        let enough = SilenceDetector.minimumVoiced
        expect(PushToTalk.outcome(voiced: enough, text: "Hello there") == .send, "PTT-3: enough voice and words: send")
        expect(PushToTalk.outcome(voiced: enough + 3, text: "42") == .send, "PTT-3: digits are words")
        expect(PushToTalk.outcome(voiced: enough - 0.01, text: "Hello there") == .discard, "PTT-3: too little voice: discard")
        expect(PushToTalk.outcome(voiced: 0, text: "Hello") == .discard, "PTT-3: no voice: discard")
        expect(PushToTalk.outcome(voiced: enough + 2, text: "…") == .discard, "PTT-3: noise marks only: discard")
        expect(PushToTalk.outcome(voiced: enough + 2, text: "") == .discard, "PTT-3: no text: discard")
        expect(PushToTalk.outcome(voiced: enough + 2, text: "  . ") == .discard, "PTT-3: blanks and a dot: discard")
        expect(PushToTalk.foldsBack(openedByPress: true, outcome: .discard), "PTT-3: opened by the press and nothing sent: fold back")
        expect(!PushToTalk.foldsBack(openedByPress: true, outcome: .send), "PTT-3: a sent phrase keeps the notch open")
        expect(!PushToTalk.foldsBack(openedByPress: false, outcome: .discard), "PTT-3: it was open before: it stays")
        expect(!PushToTalk.foldsBack(openedByPress: false, outcome: .send), "PTT-3: open before and sent: it stays")
    }
}
#endif
