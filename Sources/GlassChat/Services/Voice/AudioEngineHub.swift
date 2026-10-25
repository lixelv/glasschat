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
    }

    /// Something starts recording or playing; the engine runs until every user released it.
    func acquire() throws {
        configure()
        idleStop?.cancel()
        users += 1
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { users -= 1; throw error }
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
