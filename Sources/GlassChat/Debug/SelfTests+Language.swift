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
    }
}
#endif
