#if DEBUG
import Foundation
import Supertonic

extension SelfTests {
    static func voice() {
        expect(RecognitionMode.migrated("localWhisper") == .whisper, "local Whisper becomes WhisperKit")
        expect(RecognitionMode.migrated("whisper") == .whisper, "whisper stays")
        expect(RecognitionMode.migrated("provider") == .builtIn && RecognitionMode.migrated("audioToModel") == .builtIn, "removed modes become Apple")
        expect(RecognitionMode.migrated(nil) == .builtIn, "Apple by default")
        expect(SupertonicLanguage.language(for: "Два плюс два будет четыре.") == .russian, "Russian text")
        expect(SupertonicLanguage.language(for: "Two plus two is four.") == .english, "English text")
        expect(SupertonicLanguage.language(for: "1234") == .unspecified, "no language: na")
    }
}
#endif
