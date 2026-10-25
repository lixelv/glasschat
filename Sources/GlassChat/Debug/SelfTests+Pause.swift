#if DEBUG
import Foundation

extension SelfTests {
    static func pause() {
        func near(_ a: TimeInterval, _ b: TimeInterval) -> Bool { abs(a - b) < 0.001 }
        expect(["Привет.", "Как дела?", "Ура!", "Ну…"].allSatisfy { near(PhrasePause.seconds(for: $0, base: 0.7), 0.5) }, "a sentence: 0.5 s")
        expect(near(PhrasePause.seconds(for: "Включи свет на", base: 0.7), 0.9), "cut off mid-sentence: 0.9 s")
        expect(near(PhrasePause.seconds(for: "", base: 0.7), 0.7), "no words yet: the base")
        expect(near(PhrasePause.seconds(for: "Готово.", base: 1.4), 1.0) && near(PhrasePause.seconds(for: "и потом", base: 1.4), 1.8), "scaled with the base")
        var detector = SilenceDetector(SilenceDetector.Config(silence: 2))
        detector.setSilence(0.5)
        var t = 0.0, ended: TimeInterval?
        for (db, seconds) in [(-60.0, 1.0), (-30.0, 0.5), (-60.0, 1.5)] {
            let end = t + seconds
            while t < end - 1e-9 { if detector.feed(db, at: t) == .phraseEnded { ended = t }; t += 0.02 }
        }
        expect(ended.map { abs($0 - 2.0) <= 0.03 } == true, "a new pause applies to the phrase being recorded")
    }
}
#endif
