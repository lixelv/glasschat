import AVFoundation
import Observation
import os

let voiceLog = Logger(subsystem: "dev.lixelv.glasschat", category: "voice")

/// A phrase recorded for the assistant: 16 kHz mono 16-bit WAV in the temporary folder.
struct Recording: Sendable {
    let url: URL
    let duration: TimeInterval
}

enum VoiceError: LocalizedError {
    case microphoneDenied, noInput, languageUnsupported(String), engine(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "GlassChat needs the microphone: System Settings → Privacy & Security → Microphone."
        case .noInput: "No microphone was found."
        case .languageUnsupported(let locale): "Apple recognition does not know \(locale). Set a transcription model in Settings → Assistant."
        case .engine(let message): message
        }
    }
}

/// Records one phrase from the microphone: it ends on its own after a pause (`SilenceDetector`).
@Observable
@MainActor
final class VoiceRecorder {
    static let shared = VoiceRecorder()

    /// The input level, 0…1 (−60…−10 dBFS).
    private(set) var level = 0.0
    private(set) var isRecording = false

    private let engine = AVAudioEngine()
    private var detector = SilenceDetector(.init())
    private var writer: PhraseWriter?
    private var continuation: CheckedContinuation<Recording?, Never>?

    private init() {}

    static func requestAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    func inputFormat() throws -> AVAudioFormat {
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw VoiceError.noInput }
        return format
    }

    /// The phrase once it ended, or nil when no speech started in time or it was cancelled.
    /// `onBuffer` gets every microphone buffer, on the audio thread.
    func record(_ config: SilenceDetector.Config, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws -> Recording? {
        end(nil)
        let format = try inputFormat()
        let url = FileManager.default.temporaryDirectory.appending(path: "glasschat-phrase-\(UUID().uuidString).wav")
        let writer: PhraseWriter
        do { writer = try PhraseWriter(url: url, input: format, onBuffer: onBuffer) }
        catch { throw VoiceError.engine(error.localizedDescription) }
        detector = SilenceDetector(config)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(writer, recorder: self))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw VoiceError.engine(error.localizedDescription)
        }
        self.writer = writer
        isRecording = true
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isRecording { self.continuation = continuation } else { continuation.resume(returning: nil) }
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func cancel() {
        end(nil)
    }

    /// Made outside the main actor: the engine calls it on its own thread.
    private nonisolated static func tap(_ writer: PhraseWriter, recorder: VoiceRecorder) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let (db, time) = writer.write(buffer) else { return }
            Task { @MainActor in recorder.heard(db, at: time) }
        }
    }

    private func heard(_ db: Double, at time: TimeInterval) {
        guard isRecording else { return }
        level = min(max((db + 60) / 50, 0), 1)
        let event = detector.feed(db, at: time)
        if Int(time * 50) % 10 == 0 || event != nil {
            voiceLog.debug("t=\(time, format: .fixed(precision: 2)) db=\(db, format: .fixed(precision: 1)) floor=\(self.detector.floor, format: .fixed(precision: 1)) speaking=\(self.detector.speaking) event=\(String(describing: event), privacy: .public)")
        }
        switch event {
        case .phraseEnded?: end(writer.map { Recording(url: $0.url, duration: time) })
        case .noSpeech?: end(nil)
        default: break
        }
    }

    private func end(_ result: Recording?) {
        if isRecording {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        isRecording = false
        level = 0
        if let writer {
            writer.close()
            if result == nil { try? FileManager.default.removeItem(at: writer.url) }
        }
        writer = nil
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// Writes the microphone buffers as 16 kHz mono WAV and measures them; used on the audio thread.
private final class PhraseWriter: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private let converter: AVAudioConverter?
    private let output: AVAudioFormat
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private var frames: AVAudioFramePosition = 0

    init(url: URL, input: AVAudioFormat, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        self.url = url
        self.onBuffer = onBuffer
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        self.file = file
        output = file.processingFormat
        converter = AVAudioConverter(from: input, to: output)
    }

    /// The level in dBFS and the time from the start, after the buffer.
    func write(_ buffer: AVAudioPCMBuffer) -> (Double, TimeInterval)? {
        onBuffer(buffer)
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return nil }
        if let converter {
            let ratio = output.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            if let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) {
                var given = false
                converter.convert(to: converted, error: nil) { _, status in
                    if given { status.pointee = .noDataNow; return nil }
                    given = true
                    status.pointee = .haveData
                    return buffer
                }
                try? file.write(from: converted)
            }
        }
        frames += AVAudioFramePosition(buffer.frameLength)
        return (Self.decibels(buffer), Double(frames) / buffer.format.sampleRate)
    }

    func close() {
        lock.lock()
        file = nil
        lock.unlock()
    }

    private static func decibels(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return -100 }
        let samples = UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))
        let rms = (samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
        return rms > 0 ? max(20 * log10(rms), -100) : -100
    }
}
