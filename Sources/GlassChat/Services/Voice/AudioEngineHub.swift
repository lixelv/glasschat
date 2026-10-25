@preconcurrency import AVFoundation
import Observation

/// One audio engine for the microphone and the assistant's voice, with macOS voice processing on its input: the
/// echo canceller then takes the assistant's own voice out of what the microphone hears (needed to interrupt it).
/// It runs while something records or plays, and stops after a while without either (the microphone indicator
/// should not stay on).
@MainActor
final class AudioEngineHub {
    static let shared = AudioEngineHub()

    let engine = AVAudioEngine()
    /// Where the assistant's voice is played.
    let player = AVAudioPlayerNode()
    /// The player's format; the voice is converted to it.
    let playerFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    /// The echo canceller is on (it may be refused, e.g. by some audio interfaces).
    private(set) var echoCancellation = false

    private var configured = false
    private var users = 0
    private var idleStop: Task<Void, Never>?

    private init() {}

    /// Voice processing has to be set before the engine first runs; done once.
    func configure() {
        guard !configured else { return }
        configured = true
        // The output has to exist before voice processing is on: made after, it has no format and the engine fails
        // to start (-10875).
        _ = engine.outputNode
        _ = engine.mainMixerNode
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            // Voice processing turns other apps down (music, calls); keep that to the least.
            engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
            echoCancellation = true
        } catch {
            voiceLog.error("voice processing unavailable: \(error.localizedDescription, privacy: .public)")
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playerFormat)
        // Another device (headphones plugged in, AirPods connecting) stops the engine: what records or plays
        // through it would wait forever.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            MainActor.assumeIsolated { AudioEngineHub.shared.configurationChanged() }
        }
    }

    private func configurationChanged() {
        guard users > 0, !engine.isRunning else { return }
        voiceLog.error("audio device changed: recording and speech stopped")
        VoiceRecorder.shared.cancel()
        Speaker.shared.stop()
    }

    /// Something starts recording or playing; the engine runs until every user released it.
    func acquire() throws {
        configure()
        idleStop?.cancel()
        users += 1
        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch where echoCancellation {
                // Some devices refuse voice processing only when it starts: go on without it (no interrupting).
                voiceLog.error("engine failed with voice processing, starting without: \(error.localizedDescription, privacy: .public)")
                try? engine.inputNode.setVoiceProcessingEnabled(false)
                echoCancellation = false
                engine.prepare()
                do { try engine.start() } catch { users -= 1; throw error }
            } catch {
                users -= 1
                throw error
            }
        }
        if !player.isPlaying { player.play() }
    }

    func release() {
        users = max(users - 1, 0)
        guard users == 0 else { return }
        // Stopping and starting voice processing takes a while: wait for the next phrase first.
        idleStop?.cancel()
        idleStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled, self.users == 0 else { return }
            self.player.stop()
            self.engine.stop()
        }
    }
}

extension AVAudioConverter {
    /// A converter for microphone buffers. The echo-cancelled input has 9 channels with the voice in the first; to
    /// mono the converter on its own maps none of them and writes silence, so the first is taken.
    static func microphone(_ input: AVAudioFormat, to output: AVAudioFormat) -> AVAudioConverter? {
        let converter = AVAudioConverter(from: input, to: output)
        if input.channelCount > 1, output.channelCount == 1 { converter?.channelMap = [0] }
        return converter
    }
}
