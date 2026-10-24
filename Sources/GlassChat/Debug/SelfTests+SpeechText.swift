#if DEBUG
import Foundation

extension SelfTests {
    static func speechText() {
        expect(SpeechText.plain("# Title\n**bold** and `code` [link](http://x)") == "Title\nbold and code link", "markup removed")
        expect(SpeechText.plain("Before\n```swift\nlet x = 1\n```\nAfter") == "Before\nAfter", "code blocks dropped")
        expect(SpeechText.plain("- one\n- two") == "one\ntwo", "bullets removed")
        expect(SpeechText.plain("![img](a.png) $x^2$ ~~old~~ _it_") == "x^2 old it", "images, math, strike, italics")
    }
}
#endif
