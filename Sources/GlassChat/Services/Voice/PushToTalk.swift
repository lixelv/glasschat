import AppKit

/// The notch as a walkie-talkie: it hears only while the talk shortcut is held, and releasing it sends the phrase.
enum PushToTalk {
    enum Edge: Equatable { case press, release, cancel }

    /// Whether the talk shortcut is held, from the keyboard's events. Exactly its keys count: another key or an
    /// extra modifier while it is held means another shortcut (⌥⌘Esc), and the phrase is cancelled.
    struct Tracker {
        private let shortcut: Shortcut
        private let chord: NSEvent.ModifierFlags
        private(set) var isHeld = false
        /// The modifiers down now.
        private var modifiers: NSEvent.ModifierFlags = []
        /// Modifiers alone: the chord was cancelled (or part of another shortcut) and must be let go entirely first.
        private var spoiled = false

        init(_ shortcut: Shortcut) {
            self.shortcut = shortcut
            chord = shortcut.modifiers
        }

        mutating func flagsChanged(_ flags: NSEvent.ModifierFlags) -> Edge? {
            let now = flags.intersection(Shortcut.relevant)
            let previous = modifiers
            modifiers = now
            if isHeld {
                guard now != chord else { return nil }
                isHeld = false
                // An extra modifier: another shortcut; one let go: the phrase is over.
                if now.isSuperset(of: chord) {
                    if shortcut.keyCode == nil { spoiled = true }
                    return .cancel
                }
                return .release
            }
            guard shortcut.keyCode == nil else { return nil }
            if spoiled {
                if now.intersection(chord).isEmpty { spoiled = false }
                return nil
            }
            // Coming down to the chord from more modifiers is the end of another shortcut, not this one.
            if now == chord, !previous.isStrictSuperset(of: chord) {
                isHeld = true
                return .press
            }
            if now.isStrictSuperset(of: chord) { spoiled = true }
            return nil
        }

        mutating func keyDown(_ keyCode: UInt32, isRepeat: Bool) -> Edge? {
            guard let key = shortcut.keyCode else {
                // Modifiers alone: a key pressed with them makes another shortcut.
                if isHeld {
                    isHeld = false
                    spoiled = true
                    return .cancel
                }
                if !modifiers.intersection(chord).isEmpty { spoiled = true }
                return nil
            }
            if keyCode == key {
                guard !isHeld, !isRepeat, modifiers == chord else { return nil }
                isHeld = true
                return .press
            }
            guard isHeld else { return nil }
            isHeld = false
            return .cancel
        }

        mutating func keyUp(_ keyCode: UInt32) -> Edge? {
            guard isHeld, let key = shortcut.keyCode, keyCode == key else { return nil }
            isHeld = false
            return .release
        }
    }

    enum Outcome: Equatable { case send, discard }

    /// When the shortcut is let go: words said are sent; nothing (or noise) is dropped.
    static func outcome(voiced: TimeInterval, text: String) -> Outcome {
        voiced >= SilenceDetector.minimumVoiced && SpeechText.isWords(text) ? .send : .discard
    }
}
