import Foundation

/// Interrupting the assistant by speaking: only real words count, not a cough, a noise phrase, or the
/// assistant's own voice the echo canceller let through.
enum BargeIn {
    static let minimumVoiced: TimeInterval = 0.4

    /// `spoken`: what the assistant has said aloud in this answer.
    static func isMeaningful(heard: String, voiced: TimeInterval, spoken: String) -> Bool {
        guard voiced >= minimumVoiced, !WhisperFilter.isNoise(heard) else { return false }
        let words = Self.words(heard)
        guard words.count >= 2 || words.first.map({ $0.count >= 3 }) == true else { return false }
        // Echo: most of its longer words are the assistant's own.
        let long = words.filter { $0.count >= 3 }
        guard !long.isEmpty else { return true }
        let said = Set(Self.words(spoken))
        let echoed = long.filter(said.contains).count
        return Double(echoed) / Double(long.count) < 0.5
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
