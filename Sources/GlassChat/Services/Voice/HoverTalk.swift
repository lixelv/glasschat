import Foundation

/// The notch as a walkie-talkie: resting the pointer on it records, moving away ends the phrase.
enum HoverTalk {
    enum Outcome: Equatable { case open, discard }

    /// Whether resting on the folded notch for `hovered` seconds starts recording (passing over it does not).
    static func shouldStart(hovered: TimeInterval, delay: TimeInterval, enabled: Bool, expanded: Bool, busy: Bool) -> Bool {
        enabled && !expanded && !busy && hovered >= delay
    }

    /// When the pointer leaves: something said opens the notch with it; nothing stays folded and is dropped.
    static func outcome(voiced: TimeInterval) -> Outcome {
        voiced >= SilenceDetector.minimumVoiced ? .open : .discard
    }
}
