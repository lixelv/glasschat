#if DEBUG
import Foundation

extension SelfTests {
    static func speechText() {
        expect(SpeechText.plain("# Title\n**bold** and `code` [link](http://x)") == "Title\nbold and code link", "markup removed")
        expect(SpeechText.plain("Before\n```swift\nlet x = 1\n```\nAfter") == "Before\nAfter", "code blocks dropped")
        expect(SpeechText.plain("- one\n- two") == "one\ntwo", "bullets removed")
        expect(SpeechText.plain("![img](a.png) $x^2$ ~~old~~ _it_") == "x^2 old it", "images, math, strike, italics")

        // Punctuation alone is what recognisers make of noise.
        expect(!SpeechText.isWords("."), "a dot is not words")
        expect(!SpeechText.isWords(" … "), "an ellipsis is not words")
        expect(SpeechText.isWords("Да"), "a short word is")
        expect(SpeechText.isWords("42"), "a number is")
        // The voice follows the language of the text, not the system's.
        expect(SpeechText.language(of: "Два плюс два будет четыре.") == "ru", "Russian text")
        expect(SpeechText.language(of: "Two plus two is four.") == "en", "English text")
        expect(SpeechText.voiceMatches("ru-RU", text: "ru"), "Russian voice for Russian")
        expect(!SpeechText.voiceMatches("en-US", text: "ru"), "English voice is not for Russian")
    }
}
#endif
