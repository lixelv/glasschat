import Foundation
import NaturalLanguage

/// The words of an answer to read aloud: Markdown marks, code blocks and images left out.
enum SpeechText {
    static func plain(_ markdown: String) -> String {
        var text = markdown
        let rules: [(String, String)] = [
            (#"(?s)```.*?```"#, ""),                    // code blocks
            (#"!\[[^\]]*\]\([^)]*\)"#, ""),             // images
            (#"\[([^\]]*)\]\([^)]*\)"#, "$1"),          // links: their text
            (#"(?m)^\s{0,3}#{1,6}\s*"#, ""),            // headings
            (#"(?m)^\s*(?:[-*+]|\d+\.)\s+"#, ""),       // list items
            (#"\*\*|__|~~|[*_`$]"#, ""),                // emphasis, code, math
            (#"[ \t]+"#, " "),
            (#"(?m)^ | $"#, ""),
            (#"\n{2,}"#, "\n"),
        ]
        for (pattern, template) in rules {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The language a text is written in ("ru", "en"), to pick a voice that can read it.
    static func language(of text: String) -> String? {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
    }

    /// Whether a voice's language ("ru-RU") is the text's language ("ru").
    static func voiceMatches(_ voiceLanguage: String, text language: String) -> Bool {
        voiceLanguage.lowercased().split(separator: "-").first.map(String.init) == language.lowercased()
    }
}
