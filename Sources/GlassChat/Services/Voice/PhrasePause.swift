import Foundation

/// How long a pause ends the phrase, from the words heard so far: shorter once they form a sentence,
/// longer while it is plainly unfinished (people pause 0.6–0.9 s mid-sentence).
enum PhrasePause {
    /// `base`: the pause in Settings (0.7 s by default); the other two scale with it.
    static func seconds(for heard: String, base: TimeInterval) -> TimeInterval {
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return base }
        let finished = [".", "?", "!", "…"].contains { text.hasSuffix($0) }
        return (finished ? 0.5 : 0.9) * base / 0.7
    }
}
