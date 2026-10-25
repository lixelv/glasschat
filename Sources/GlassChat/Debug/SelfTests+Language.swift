#if DEBUG
import Foundation

extension SelfTests {
    static func language() {
        let en = RecognitionLane.Score(text: "Kaka Esteliza Franci.", confidence: 0.31 * 21, characters: 21)
        let ru = RecognitionLane.Score(text: "Какая столица Франции?", confidence: 0.9 * 22, characters: 22)
        expect(RecognitionLane.best([en, ru])?.text == "Какая столица Франции?", "most confident language wins")
        expect(RecognitionLane.best([ru, en])?.text == "Какая столица Франции?", "order does not matter")
        let empty = RecognitionLane.Score(text: "", confidence: 0, characters: 0)
        expect(RecognitionLane.best([empty, en])?.text == "Kaka Esteliza Franci.", "empty lane loses")
        expect(RecognitionLane.best([empty]) == nil, "nothing heard")
        // Without confidences (0 everywhere) the longest text wins.
        let a = RecognitionLane.Score(text: "hi", confidence: 0, characters: 2)
        let b = RecognitionLane.Score(text: "hello there", confidence: 0, characters: 11)
        expect(RecognitionLane.best([a, b])?.text == "hello there", "no confidences: longest")
        expect(RecognitionMode.default == .builtIn, "built-in by default")

        // Whisper is told the language Apple heard the words in; with no words it detects the language itself.
        expect(WhisperLanguage.hint(appleText: "А что ты умеешь", appleLanguage: "ru") == "ru", "Apple's language for Whisper")
        expect(WhisperLanguage.hint(appleText: "", appleLanguage: "ru") == nil, "no words: Whisper detects")
        expect(WhisperLanguage.hint(appleText: nil, appleLanguage: "ru") == nil, "no Apple text: Whisper detects")
        expect(WhisperLanguage.hint(appleText: "Hello", appleLanguage: nil) == nil, "no language: Whisper detects")
        expect(WhisperLanguage.hint(appleText: "Hola", appleLanguage: "es-ES") == "es", "a region is dropped")
        let ruLane = RecognitionLane.Score(text: "привет", confidence: 5.4, characters: 6, language: "ru")
        let enLane = RecognitionLane.Score(text: "privet", confidence: 1.2, characters: 6, language: "en")
        expect(RecognitionLane.best([enLane, ruLane])?.language == "ru", "the surest lane tells the language")
    }
}
#endif
