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

        // The interruption listener: no time limit until the user interrupts, then the usual one from there.
        var unlimited = SilenceDetector.Config()
        unlimited.silence = .infinity
        unlimited.wait = .infinity
        unlimited.maxPhrase = .infinity
        var listener = SilenceDetector(unlimited)
        var limitEnded = false
        var clock = 0.0
        while clock < 100 { limitEnded = limitEnded || listener.feed(clock < 0.3 ? -70 : -30, at: clock) == .phraseEnded; clock += 0.1 }
        expect(!limitEnded, "no phrase limit while listening for an interruption")
        listener.limitPhrase(60, from: clock)
        while clock < 130 { limitEnded = limitEnded || listener.feed(-30, at: clock) == .phraseEnded; clock += 0.1 }
        expect(!limitEnded, "the limit counts from the interruption")
        while clock < 161 { limitEnded = limitEnded || listener.feed(-30, at: clock) == .phraseEnded; clock += 0.1 }
        expect(limitEnded, "the phrase ends 60 s after the interruption")

        // Voice right now: the user is still talking when the answer ends.
        var recent = SilenceDetector(unlimited)
        clock = 0
        while clock < 2 { _ = recent.feed(clock < 0.3 ? -70 : -30, at: clock); clock += 0.1 }
        expect(recent.voiceWithin(0.7, at: clock), "voice just now")
        while clock < 3 { _ = recent.feed(-70, at: clock); clock += 0.1 }
        expect(!recent.voiceWithin(0.7, at: clock), "no voice for a second")
    }
}
#endif
