import AppKit
import Carbon.HIToolbox

/// The keys held to talk to the notch assistant from any app: modifiers alone (⌥⌘) or with a key.
struct Shortcut: Codable, Equatable, Sendable {
    /// nil: the modifiers alone.
    var keyCode: UInt32?
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool
    /// What the key shows ("Space", "K"), kept from when it was recorded; empty for modifiers alone.
    var key: String

    static let standard = Shortcut(keyCode: nil, modifiers: [.option, .command], key: "")

    init(keyCode: UInt32?, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        command = modifiers.contains(.command)
        shift = modifiers.contains(.shift)
        option = modifiers.contains(.option)
        control = modifiers.contains(.control)
        self.key = key
    }

    var modifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    /// The four modifiers a shortcut is made of (not Caps Lock, Fn or the numeric pad).
    static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// "⌃ ⌥ ⇧ ⌘ K", in the order macOS menus use.
    var display: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        return (keyCode == nil || key.isEmpty ? parts : parts + [key]).joined(separator: " ")
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

    /// Modifiers alone need two of them (one is pressed all the time); a key needs a modifier, except the
    /// function keys.
    static func isValid(modifiers: NSEvent.ModifierFlags, keyCode: UInt32?) -> Bool {
        let count = [NSEvent.ModifierFlags.command, .option, .control, .shift].filter(modifiers.contains).count
        guard let keyCode else { return count >= 2 }
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        return count >= 1 || functionKeys.contains(Int(keyCode))
    }
}
