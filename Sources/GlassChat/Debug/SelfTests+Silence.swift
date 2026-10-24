#if DEBUG
import Foundation

extension SelfTests {
    static func silence() {
        func run(_ segments: [(db: Double, seconds: Double)], wait: Double = 8) -> [(SilenceDetector.Event, TimeInterval)] {
            var detector = SilenceDetector(SilenceDetector.Config(wait: wait))
            var events: [(SilenceDetector.Event, TimeInterval)] = []
            var t = 0.0
            for segment in segments {
                let end = t + segment.seconds
                while t < end - 1e-9 {
                    if let event = detector.feed(segment.db, at: t) { events.append((event, t)) }
                    t += 0.02
                }
            }
            return events
        }
        func near(_ got: [(SilenceDetector.Event, TimeInterval)], _ want: [(SilenceDetector.Event, TimeInterval)]) -> Bool {
            got.count == want.count && zip(got, want).allSatisfy { $0.0 == $1.0 && abs($0.1 - $1.1) <= 0.03 }
        }
        expect(near(run([(-60, 1), (-30, 0.5), (-60, 2)]), [(.speechStarted, 1.15), (.phraseEnded, 3.0)]), "phrase with 1.5 s pause")
        expect(near(run([(-60, 0.5), (-30, 0.1), (-60, 9)]), [(.noSpeech, 8.0)]), "blip is not speech; wait 8 s")
        expect(near(run([(-60, 16)], wait: 15), [(.noSpeech, 15.0)]), "follow-up window 15 s")
        // Talking without a real pause (only short gaps between words) for over a minute.
        let talk = [(db: -60.0, seconds: 0.5)] + Array(repeating: [(db: -30.0, seconds: 0.9), (db: -60.0, seconds: 0.1)], count: 62).flatMap { $0 }
        expect(near(run(talk), [(.speechStarted, 0.65), (.phraseEnded, 60.5)]), "phrase capped at 60 s")
        // The floor rose to -50 (under the -48 threshold): the threshold follows it.
        expect(near(run([(-60, 1), (-50, 3), (-35, 0.5), (-45, 2)]), [(.speechStarted, 4.15), (.phraseEnded, 6.0)]), "floor adapts")
        // How long the phrase was actually voiced: a short burst of noise is not speech worth sending.
        func voiced(_ segments: [(db: Double, seconds: Double)]) -> TimeInterval {
            var detector = SilenceDetector(SilenceDetector.Config())
            var t = 0.0
            for segment in segments {
                let end = t + segment.seconds
                while t < end - 1e-9 { _ = detector.feed(segment.db, at: t); t += 0.02 }
            }
            return detector.voiced
        }
        expect(abs(voiced([(-60, 1), (-30, 1.2), (-60, 2)]) - 1.2) <= 0.05, "voiced time of a phrase")
        expect(voiced([(-60, 1), (-35, 0.2), (-60, 2)]) < SilenceDetector.minimumVoiced, "a noise burst is too short")
        // A short gap between words is not the end.
        expect(near(run([(-60, 1), (-30, 0.5), (-60, 0.6), (-30, 0.5), (-60, 2)]), [(.speechStarted, 1.15), (.phraseEnded, 4.1)]), "gap between words")
        // The microphone starts nearly deaf (-68), the room is at -60: the floor follows it up, so silence ends the phrase.
        // The microphone starts nearly deaf (-68) and the room's noise (-55…-60) passes for speech at once:
        // the floor must still follow the room, so the quiet room ends the "phrase" instead of 60 s later.
        let stuck = run([(-68, 0.3), (-55, 0.2), (-60, 6)])
        expect(stuck.contains { $0.0 == .phraseEnded && $0.1 < 6 }, "deaf start, louder room ends")
    }
}
#endif
