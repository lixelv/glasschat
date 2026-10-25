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
        // Echo: most of its longer words are the assistant's own; short words only, all of them are.
        let said = Set(Self.words(spoken))
        let long = words.filter { $0.count >= 3 }
        guard !long.isEmpty else { return !words.allSatisfy(said.contains) }
        let echoed = long.filter(said.contains).count
        return Double(echoed) / Double(long.count) < 0.5
    }

    /// What was heard during an answer is judged and sent one utterance at a time: words before a pause in the
    /// live text (echo, the room) are neither counted for an interruption nor sent with it.
    struct Utterance {
        /// A pause this long between live texts starts a new utterance.
        static let pause: TimeInterval = 1.5

        /// Seconds of the recording where the current utterance's words began to come.
        private(set) var start: TimeInterval = 0
        private var base = ""
        private var voicedBase: TimeInterval = 0
        private var last = ""
        private var lastVoiced: TimeInterval = 0
        private var lastTime: TimeInterval?

        /// The live text so far and the recorder's voice at `time`: the current utterance's words and voice.
        mutating func update(_ text: String, voiced: TimeInterval, at time: TimeInterval) -> (text: String, voiced: TimeInterval) {
            if let lastTime, time - lastTime >= Self.pause {
                base = last
                voicedBase = lastVoiced
                start = time
            } else if lastTime == nil {
                start = time
            }
            // The recogniser rewrote earlier words: the base cannot be told apart, so all of it counts.
            if !text.hasPrefix(base) {
                base = ""
                voicedBase = 0
            }
            last = text
            lastVoiced = voiced
            lastTime = time
            return (String(text.dropFirst(base.count)).trimmingCharacters(in: .whitespacesAndNewlines), voiced - voicedBase)
        }

        /// The words of the current utterance in a final text of the whole recording.
        func words(of text: String) -> String {
            text.hasPrefix(base) ? String(text.dropFirst(base.count)).trimmingCharacters(in: .whitespacesAndNewlines) : text
        }
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
