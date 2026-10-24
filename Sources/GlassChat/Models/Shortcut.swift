import AppKit
import Carbon.HIToolbox

/// A key with modifiers that calls the notch assistant from any app.
struct Shortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool
    /// What the key shows ("Space", "K"), kept from when it was recorded.
    var key: String

    static let standard = Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.option], key: "Space")

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        command = modifiers.contains(.command)
        shift = modifiers.contains(.shift)
        option = modifiers.contains(.option)
        control = modifiers.contains(.control)
        self.key = key
    }

    /// The modifiers as `RegisterEventHotKey` wants them.
    var carbonModifiers: UInt32 {
        var flags = 0
        if command { flags |= cmdKey }
        if shift { flags |= shiftKey }
        if option { flags |= optionKey }
        if control { flags |= controlKey }
        return UInt32(flags)
    }

    /// "⌃ ⌥ ⇧ ⌘ K", in the order macOS menus use.
    var display: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        return (parts + [key]).joined(separator: " ")
    }

    private static let names: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete", kVK_Escape: "Esc",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func keyName(keyCode: UInt32, characters: String?) -> String {
        names[Int(keyCode)] ?? (characters ?? "").uppercased()
    }

    /// A key needs a modifier to be a shortcut, except the function keys.
    static func isValid(modifiers: NSEvent.ModifierFlags, keyCode: UInt32) -> Bool {
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        return !modifiers.intersection([.command, .option, .control, .shift]).isEmpty || functionKeys.contains(Int(keyCode))
    }
}
