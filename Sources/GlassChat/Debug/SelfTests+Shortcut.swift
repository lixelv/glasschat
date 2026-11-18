#if DEBUG
import AppKit
import Carbon.HIToolbox

extension SelfTests {
    static func shortcut() {
        // PTT-9: the default is the bare Option-Command chord.
        expect(Shortcut.standard.display == "⌥ ⌘", "PTT-9: default shows Option-Command")
        expect(Shortcut.standard.keyCode == nil && Shortcut.standard.key == "", "PTT-9: default has no key")
        expect(Shortcut.standard.modifiers == [.option, .command], "PTT-9: default modifiers")
        let all = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: [.command, .shift, .option, .control], key: "K")
        expect(all.display == "⌃ ⌥ ⇧ ⌘ K", "PTT-9: modifiers in Apple's order, then the key")
        expect(all.modifiers == [.command, .shift, .option, .control], "PTT-9: modifiers read back from the flags")
        let data = try? JSONEncoder().encode(all)
        expect(data.flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } == all, "PTT-9: saved and read back")
        let chordData = try? JSONEncoder().encode(Shortcut.standard)
        expect(chordData.flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } == Shortcut.standard, "PTT-9: a chord without a key is saved and read back")
        expect(Shortcut.standard != Shortcut(keyCode: nil, modifiers: [.option, .command, .shift], key: ""), "PTT-9: chords differ by modifiers")
        expect(Shortcut(keyCode: UInt32(kVK_F5), modifiers: [], key: "F5").display == "F5", "PTT-9: a function key alone shows just its name")
        expect(Shortcut.keyName(keyCode: UInt32(kVK_Return), characters: "\r") == "Return", "PTT-9: named keys")
        expect(Shortcut.keyName(keyCode: UInt32(kVK_ANSI_A), characters: "a") == "A", "PTT-9: letters upper-cased")

        // PTT-9: what the recorder accepts.
        expect(!Shortcut.isValid(modifiers: [], keyCode: UInt32(kVK_ANSI_A)), "PTT-9: a plain letter is not a shortcut")
        expect(Shortcut.isValid(modifiers: [], keyCode: UInt32(kVK_F5)), "PTT-9: a function key alone is")
        expect(Shortcut.isValid(modifiers: [.command], keyCode: UInt32(kVK_ANSI_K)), "PTT-9: modifier plus key is")
        expect(Shortcut.isValid(modifiers: [.option, .command], keyCode: nil), "PTT-9: two modifiers are a chord")
        expect(!Shortcut.isValid(modifiers: [.option], keyCode: nil), "PTT-9: one modifier alone is not")
        expect(!Shortcut.isValid(modifiers: [], keyCode: nil), "PTT-9: nothing is not")
        expect(Shortcut.isValid(modifiers: [.command, .shift, .option, .control], keyCode: nil), "PTT-9: all four modifiers are a chord")
    }
}
#endif
