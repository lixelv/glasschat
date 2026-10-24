import Foundation

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
}
