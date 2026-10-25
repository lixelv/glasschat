import Foundation

/// Whisper guesses the language of a short phrase badly ("А что" became Portuguese); Apple, which listened in each
/// of the user's languages, already knows it. Whisper is told that language when Apple heard words.
enum WhisperLanguage {
    /// The language code for Whisper ("ru"), or nil to let it detect the language.
    static func hint(appleText: String?, appleLanguage: String?) -> String? {
        guard let appleText, SpeechText.isWords(appleText), let appleLanguage else { return nil }
        let code = appleLanguage.lowercased().split { $0 == "-" || $0 == "_" }.first.map(String.init) ?? ""
        guard (2...3).contains(code.count), code.allSatisfy(\.isLetter) else { return nil }
        return code
    }
}
