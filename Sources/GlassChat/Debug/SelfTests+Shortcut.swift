#if DEBUG
import AppKit
import Carbon.HIToolbox

extension SelfTests {
    static func shortcut() {
        expect(Shortcut.standard.display == "⇧ Space", "default is Shift-Space")
        expect(Shortcut.standard.keyCode == UInt32(kVK_Space) && Shortcut.standard.carbonModifiers == UInt32(shiftKey), "default codes")
        let all = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: [.command, .shift, .option, .control], key: "K")
        expect(all.display == "⌃ ⌥ ⇧ ⌘ K", "modifiers in Apple's order")
        expect(all.carbonModifiers == UInt32(cmdKey | shiftKey | optionKey | controlKey), "carbon modifiers")
        let data = try? JSONEncoder().encode(all)
        expect(data.flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } == all, "saved and read back")
        expect(Shortcut.keyName(keyCode: UInt32(kVK_Return), characters: "\r") == "Return", "named keys")
        expect(Shortcut.keyName(keyCode: UInt32(kVK_ANSI_A), characters: "a") == "A", "letters upper-cased")
        expect(!Shortcut.isValid(modifiers: [], keyCode: UInt32(kVK_ANSI_A)), "a plain letter is not a shortcut")
        expect(Shortcut.isValid(modifiers: [], keyCode: UInt32(kVK_F5)), "a function key alone is")
    }
}
#endif
