@preconcurrency import AVFoundation
import Observation
import Supertonic

/// Says texts aloud: Supertonic 3 on this Mac, or the macOS voice until it is downloaded. One at a time.
@Observable
@MainActor
final class Speaker {
    static let shared = Speaker()

    private(set) var isSpeaking = false
    /// The output level, 0…1, for the avatar's mouth and the waveform.
    private(set) var level = 0.0
    /// What is being said (a message id), so its Speak button can turn into Stop.
    private(set) var speakingID: String?
    /// What was said aloud since the last message (an interruption is not its echo).
    private(set) var spoken = ""

    func resetSpoken() {
        spoken = ""
    }

    private var synthesizer: AVSpeechSynthesizer?
    private var playback: SynthPlayback?
    /// Where the voice plays: the shared engine, whose echo canceller then hears it (the microphone is on too),
    /// or an engine of its own that only plays.
    private enum Output { case shared, own(AVAudioEngine) }
    private var output: Output?
    private var sharedOutput = false
    private var done: ResumeOnce<Bool>?

    private init() {}

    /// Returns true when the text was said to the end, false when it was stopped.
    /// `interruptible`: the notch assistant may be interrupted while it speaks, so the voice goes through the
    /// shared engine with the microphone; otherwise only the speakers are used.
    @discardableResult
    func speak(_ text: String, id: String? = nil, interruptible: Bool = false) async throws -> Bool {
        stop()
        sharedOutput = interruptible
        spoken += " " + text
        let once = ResumeOnce<Bool>()
        done = once
        speakingID = id
        isSpeaking = true
        defer {
            if done === once { finishUp() }
        }
        return await withTaskCancellationHandler {
            // Supertonic once it is downloaded; until then (or if it fails) the macOS voice.
            if !(await startSupertonic(text, once: once)), done === once {
                startSystemVoice(text, once: once)
            }
            return await withCheckedContinuation { once.set($0) }
        } onCancel: {
            once.resume(false)
            Task { @MainActor in Speaker.shared.stopIfCurrent(once) }
        }
    }

    func stop() {
        done?.resume(false)
        finishUp()
    }

    private func stopIfCurrent(_ once: ResumeOnce<Bool>) {
        if done === once { stop() }
    }

    private func finishUp() {
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        playback?.stop()
        switch output {
        case .shared?: AudioEngineHub.shared.release()
        case .own(let engine)?: engine.stop()
        case nil: break
        }
        output = nil
        playback = nil
        done = nil
        isSpeaking = false
        speakingID = nil
        level = 0
    }

    /// Synthesizes the whole text, then plays it; false when Supertonic cannot (not downloaded, failed).
    private func startSupertonic(_ text: String, once: ResumeOnce<Bool>) async -> Bool {
        guard VoiceModels.shared.speech == .ready, let synthesizer = try? VoiceModels.shared.synthesizer() else { return false }
        let voice = Voice(rawValue: AppSettings.shared.supertonicVoice) ?? .female1
        let language = SupertonicLanguage.language(for: text)
        // Short replies (app_say) start sooner with fewer synthesis steps.
        let options = SynthesisOptions(quality: text.count <= 200 ? .fast : .balanced)
        guard let audio = try? await synthesizer.synthesize(text, in: language, with: voice, options: options), !audio.samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: Double(audio.sampleRate), channels: 1) else {
            voiceLog.error("Supertonic failed; the macOS voice speaks")
            return false
        }
        guard done === once, let playback = makePlayback(once) else { return done === once ? false : true }
        // In pieces, so the avatar's mouth follows the voice.
        let piece = 2048
        var start = 0
        while start < audio.samples.count {
            let count = min(piece, audio.samples.count - start)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { break }
            buffer.frameLength = AVAudioFrameCount(count)
            audio.samples.withUnsafeBufferPointer { samples in
                buffer.floatChannelData![0].update(from: samples.baseAddress! + start, count: count)
            }
            playback.receive(buffer)
            start += count
        }
        if let end = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) { playback.receive(end) }
        return true
    }

    /// Plays through the shared engine (the echo canceller hears the assistant's own voice) or one of its own.
    private func makePlayback(_ once: ResumeOnce<Bool>) -> SynthPlayback? {
        let player: AVAudioPlayerNode
        let format: AVAudioFormat
        do {
            if sharedOutput {
                let hub = AudioEngineHub.shared
                try hub.acquire()
                output = .shared
                (player, format) = (hub.player, hub.playerFormat)
            } else {
                let engine = AVAudioEngine()
                (player, format) = (AVAudioPlayerNode(), AudioEngineHub.shared.playerFormat)
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                try engine.start()
                player.play()
                output = .own(engine)
            }
        } catch {
            voiceLog.error("audio engine failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let playback = SynthPlayback(
            player: player, format: format,
            onLevel: { level in Task { @MainActor in Speaker.shared.setLevel(level, if: once) } },
            onDone: { once.resume(true) })
        self.playback = playback
        return playback
    }

    private func startSystemVoice(_ text: String, once: ResumeOnce<Bool>) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: text)
        guard let playback = makePlayback(once) else { once.resume(false); return }
        let synthesizer = AVSpeechSynthesizer()
        self.synthesizer = synthesizer
        synthesizer.write(utterance, toBufferCallback: Self.callback(playback))
    }

    /// The voice of Settings when it speaks the text's language, else the best voice of that language
    /// (a voice of another language spells the text letter by letter).
    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let chosen = AppSettings.shared.systemVoice.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: AppSettings.shared.systemVoice)
        guard let language = SpeechText.language(of: text) else {
            return chosen ?? AVSpeechSynthesisVoice(language: Locale.current.identifier(.bcp47))
        }
        if let chosen, SpeechText.voiceMatches(chosen.language, text: language) { return chosen }
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { SpeechText.voiceMatches($0.language, text: language) }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }

    /// Made outside the main actor: the synthesizer calls it on its own thread.
    private nonisolated static func callback(_ playback: SynthPlayback) -> AVSpeechSynthesizer.BufferCallback {
        { buffer in playback.receive(buffer) }
    }

    private func setLevel(_ value: Double, if once: ResumeOnce<Bool>) {
        if done === once { level = value }
    }
}

/// Plays the buffers the synthesizer writes and measures them; used on the synthesizer's and the engine's threads.
private final class SynthPlayback: @unchecked Sendable {
    private let lock = NSLock()
    private let player: AVAudioPlayerNode
    /// The player's format: every buffer is converted to it.
    private let format: AVAudioFormat
    private var converter: AVAudioConverter?
    private var scheduled = 0
    private var played = 0
    private var ended = false
    private var finished = false
    private let onLevel: @Sendable (Double) -> Void
    private let onDone: @Sendable () -> Void

    init(player: AVAudioPlayerNode, format: AVAudioFormat,
         onLevel: @escaping @Sendable (Double) -> Void, onDone: @escaping @Sendable () -> Void) {
        self.player = player
        self.format = format
        self.onLevel = onLevel
        self.onDone = onDone
    }

    func receive(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, let pcm = buffer as? AVAudioPCMBuffer else { return }
        guard pcm.frameLength > 0 else {
            ended = true
            checkDone()
            return
        }
        guard let playable = converted(pcm) else { return }
        scheduled += 1
        let level = Self.level(playable)
        player.scheduleBuffer(playable, completionCallbackType: .dataPlayedBack) { [self] _ in
            onLevel(level)
            lock.lock()
            played += 1
            checkDone()
            lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        finished = true
        lock.unlock()
        // What was scheduled for this text is dropped; the next text starts the player again (`acquire`).
        player.stop()
    }

    /// Under the lock.
    private func checkDone() {
        guard ended, played == scheduled, !finished else { return }
        finished = true
        onLevel(0)
        onDone()
    }

    /// The buffer in the player's format (rate and sample type), whatever the synthesizer wrote.
    private func converted(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if pcm.format == format { return pcm }
        if converter == nil || converter?.inputFormat != pcm.format { converter = AVAudioConverter(from: pcm.format, to: format) }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * format.sampleRate / pcm.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var given = false
        converter.convert(to: out, error: nil) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return pcm
        }
        return out.frameLength > 0 ? out : nil
    }

    private static func level(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))
        let rms = (samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
        let db = rms > 0 ? 20 * log10(rms) : -100
        return min(max((db + 50) / 45, 0), 1)
    }
}
