#if DEBUG
import Foundation

extension SelfTests {
    static func hallucination() {
        // Apple heard nothing: Whisper's text is made of noise.
        expect(!WhisperFilter.accept("Продолжение следует...", apple: ""), "Apple heard nothing: dropped")
        expect(!WhisperFilter.accept("Thank you.", apple: "."), "Apple heard only punctuation: dropped")
        // Apple heard words: Whisper's (better) text is kept, also a short real "Спасибо".
        expect(WhisperFilter.accept("Какая сегодня погода в Таллине?", apple: "Какая сегодня погода в Таллине"), "real speech kept")
        expect(WhisperFilter.accept("Спасибо.", apple: "Спасибо"), "a real thank-you is kept")
        // Without Apple: only Whisper's well-known noise phrases are dropped.
        expect(!WhisperFilter.accept("Thank you.", apple: nil) && !WhisperFilter.accept("Продолжение следует...", apple: nil)
               && !WhisperFilter.accept("Субтитры сделал DimaTorzok", apple: nil) && !WhisperFilter.accept("Gracias.", apple: nil),
               "known noise phrases dropped without Apple")
        expect(WhisperFilter.accept("Включи свет на кухне", apple: nil), "ordinary text kept without Apple")
        // Apple's English recogniser has noise phrases of its own.
        expect(!WhisperFilter.accept("Thank you.", apple: "Thank you."), "both heard a noise phrase: dropped")
        expect(WhisperFilter.isNoise("Hmm.") && WhisperFilter.isNoise("Thank you.") && !WhisperFilter.isNoise("Thank you, that works"), "noise phrases")
    }
}
#endif
