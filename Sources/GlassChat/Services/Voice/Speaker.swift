@preconcurrency import AVFoundation
import Observation

/// Says texts aloud: the macOS voice, or the TTS model of Settings (`/audio/speech`). One at a time.
@Observable
@MainActor
final class Speaker {
    static let shared = Speaker()

    private(set) var isSpeaking = false
    /// The output level, 0…1, for the avatar's mouth and the waveform.
    private(set) var level = 0.0
    /// What is being said (a message id), so its Speak button can turn into Stop.
    private(set) var speakingID: String?

    private var synthesizer: AVSpeechSynthesizer?
    private var playback: SynthPlayback?
    private var player: AVAudioPlayer?
    private var playerDelegate: PlayerDelegate?
    private var meter: Task<Void, Never>?
    private var done: ResumeOnce<Bool>?

    private init() {}

    /// Returns true when the text was said to the end, false when it was stopped.
    @discardableResult
    func speak(_ text: String, id: String? = nil) async throws -> Bool {
        stop()
        let once = ResumeOnce<Bool>()
        done = once
        speakingID = id
        isSpeaking = true
        defer {
            if done === once { finishUp() }
        }
        let settings = AppSettings.shared
        let endpoint = settings.endpoint(.speech)
        return try await withTaskCancellationHandler {
            if let endpoint {
                let client = OpenAIClient(baseURL: endpoint.url, token: endpoint.token)
                let voice = settings.ttsVoice.trimmingCharacters(in: .whitespaces)
                let data = try await client.speech(text, model: endpoint.model, voice: voice.isEmpty ? "alloy" : voice)
                guard done === once else { return false }
                try startPlayer(data, once: once)
            } else {
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
        playback = nil
        player?.stop()
        player = nil
        playerDelegate = nil
        meter?.cancel()
        meter = nil
        done = nil
        isSpeaking = false
        speakingID = nil
        level = 0
    }

    private func startSystemVoice(_ text: String, once: ResumeOnce<Bool>) {
        let utterance = AVSpeechUtterance(string: text)
        let id = AppSettings.shared.systemVoice
        utterance.voice = (id.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: id))
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier(.bcp47))
        let playback = SynthPlayback(
            onLevel: { level in Task { @MainActor in Speaker.shared.setLevel(level, if: once) } },
            onDone: { once.resume(true) })
        let synthesizer = AVSpeechSynthesizer()
        self.playback = playback
        self.synthesizer = synthesizer
        synthesizer.write(utterance, toBufferCallback: Self.callback(playback))
    }

    /// Made outside the main actor: the synthesizer calls it on its own thread.
    private nonisolated static func callback(_ playback: SynthPlayback) -> AVSpeechSynthesizer.BufferCallback {
        { buffer in playback.receive(buffer) }
    }

    private func setLevel(_ value: Double, if once: ResumeOnce<Bool>) {
        if done === once { level = value }
    }

    private func startPlayer(_ data: Data, once: ResumeOnce<Bool>) throws {
        let player = try AVAudioPlayer(data: data)
        let delegate = PlayerDelegate { once.resume(true) }
        player.delegate = delegate
        player.isMeteringEnabled = true
        self.player = player
        playerDelegate = delegate
        player.play()
        meter = Task { @MainActor [weak player] in
            while !Task.isCancelled, let player {
                player.updateMeters()
                self.level = min(max((Double(player.averagePower(forChannel: 0)) + 50) / 50, 0), 1)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let finished: @Sendable () -> Void
    init(_ finished: @escaping @Sendable () -> Void) { self.finished = finished }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finished() }
}

/// Plays the buffers the synthesizer writes and measures them; used on the synthesizer's and the engine's threads.
private final class SynthPlayback: @unchecked Sendable {
    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var scheduled = 0
    private var played = 0
    private var ended = false
    private var finished = false
    private let onLevel: @Sendable (Double) -> Void
    private let onDone: @Sendable () -> Void

    init(onLevel: @escaping @Sendable (Double) -> Void, onDone: @escaping @Sendable () -> Void) {
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
        guard let playable = floatBuffer(pcm) else { return }
        if format == nil {
            format = playable.format
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playable.format)
            do { try engine.start() } catch { finished = true; onDone(); return }
            player.play()
        }
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
        player.stop()
        engine.stop()
    }

    /// Under the lock.
    private func checkDone() {
        guard ended, played == scheduled, !finished else { return }
        finished = true
        onLevel(0)
        onDone()
    }

    /// The player node plays float samples; the synthesizer often writes 16-bit ones.
    private func floatBuffer(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if pcm.format.commonFormat == .pcmFormatFloat32 { return pcm }
        guard let target = AVAudioFormat(standardFormatWithSampleRate: pcm.format.sampleRate, channels: pcm.format.channelCount) else { return nil }
        if converter == nil { converter = AVAudioConverter(from: pcm.format, to: target) }
        guard let converter, let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: pcm.frameLength) else { return nil }
        do { try converter.convert(to: out, from: pcm) } catch { return nil }
        return out
    }

    private static func level(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))
        let rms = (samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
        let db = rms > 0 ? 20 * log10(rms) : -100
        return min(max((db + 50) / 45, 0), 1)
    }
}
