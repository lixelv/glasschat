import Foundation

/// Finds where a phrase starts and ends in a stream of levels: speech is well above the background
/// noise (which it follows while nobody speaks), the end is a long enough quiet stretch.
struct SilenceDetector {
    struct Config: Sendable {
        /// Seconds at the start that only measure the noise.
        var calibration = 0.3
        /// dB above the noise that start speech, held for `startHold` seconds.
        var startMargin = 12.0
        var startHold = 0.15
        /// dB above the noise under which speech counts as silence, for `silence` seconds.
        var endMargin = 6.0
        var silence = 1.5
        var maxPhrase = 60.0
        /// dB per second the noise floor may rise while speaking.
        var floorRise = 4.0
        /// Seconds to wait for speech to start.
        var wait = 8.0
    }

    enum Event: Equatable { case speechStarted, phraseEnded, noSpeech }

    private let config: Config
    private(set) var floor = -50.0
    private(set) var speaking = false
    private var calibrationSum = 0.0
    private var calibrationCount = 0
    private var aboveSince: TimeInterval?
    private var belowSince: TimeInterval?
    private var speechStart: TimeInterval = 0
    private var done = false
    private var lastTime: TimeInterval?

    init(_ config: Config) {
        self.config = config
    }

    /// `db` in dBFS, `time` in seconds from the start of the recording.
    mutating func feed(_ db: Double, at time: TimeInterval) -> Event? {
        guard !done else { return nil }
        let eps = 1e-6
        let dt = lastTime.map { time - $0 } ?? 0
        lastTime = time
        if time < config.calibration {
            calibrationSum += db
            calibrationCount += 1
            floor = calibrationSum / Double(calibrationCount)
            return nil
        }
        if !speaking {
            if db > floor + config.startMargin {
                let since = aboveSince ?? time
                aboveSince = since
                if time - since >= config.startHold - eps {
                    speaking = true
                    speechStart = since
                    return .speechStarted
                }
            } else {
                aboveSince = nil
                floor = floor * 0.95 + db * 0.05
            }
            if time >= config.wait - eps {
                done = true
                return .noSpeech
            }
            return nil
        }
        // While speaking the floor still follows the room: down to any quieter moment, slowly up otherwise
        // (a start measured on a nearly deaf microphone, or a room that got louder, would never end the phrase).
        floor = db < floor ? db : min(floor + config.floorRise * dt, db)
        if time - speechStart >= config.maxPhrase - eps {
            done = true
            return .phraseEnded
        }
        if db < floor + config.endMargin {
            let since = belowSince ?? time
            belowSince = since
            if time - since >= config.silence - eps {
                done = true
                return .phraseEnded
            }
        } else {
            belowSince = nil
        }
        return nil
    }
}
