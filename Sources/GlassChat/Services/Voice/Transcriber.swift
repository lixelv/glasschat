@preconcurrency import AVFoundation
import Speech
@preconcurrency import WhisperKit

/// How the assistant turns speech into text.
enum RecognitionMode: String, CaseIterable, Codable, Sendable {
    /// Apple's recognition on this Mac, in the languages of the system.
    case builtIn
    /// whisper-large-v3-turbo on this Mac (WhisperKit); Apple shows the words while they are spoken.
    case whisper

    static let `default` = RecognitionMode.builtIn

    /// Saved modes of earlier versions: their local Whisper is this one; the rest are Apple's.
    static func migrated(_ raw: String?) -> RecognitionMode {
        switch raw {
        case "whisper", "localWhisper": .whisper
        default: .builtIn
        }
    }

    var title: String {
        switch self {
        case .builtIn: "Apple (built-in)"
        case .whisper: "Whisper large-v3-turbo"
        }
    }

    var detail: String {
        switch self {
        case .builtIn: "Free and instant. Listens in the languages of System Settings and keeps the surest."
        case .whisper: "On this Mac, any language, more accurate; about a second after you stop talking."
        }
    }
}

/// Turns one recorded phrase into text: live while it is spoken (Apple) and finally after it.
@MainActor
protocol TranscriptionSession: AnyObject, Sendable {
    /// Every microphone buffer, on the audio thread.
    nonisolated func append(_ buffer: AVAudioPCMBuffer)
    func finish(_ recording: Recording) async throws -> String
    func cancel()
}

enum Transcription {
    /// Apple always shows the words while they are spoken; with Whisper that one writes the final text,
    /// and Apple's stands in when it fails.
    @MainActor
    static func start(inputFormat: AVAudioFormat, onPartial: @escaping @MainActor (String) -> Void,
                      onProgress: @escaping @MainActor (Double?) -> Void) async throws -> any TranscriptionSession {
        let mode = AppSettings.shared.recognitionMode
        let apple: AppleTranscription?
        do {
            apple = try await AppleTranscription.start(locales: await languages(), onPartial: onPartial, onProgress: onProgress)
        } catch {
            guard mode != .builtIn else { throw error }
            apple = nil
        }
        guard mode == .whisper, VoiceModels.shared.whisper == .ready else {
            // Until Whisper is downloaded, Apple hears.
            guard let apple else { throw VoiceError.engine("Apple recognition could not start.") }
            return apple
        }
        return FinalTranscription(fallback: apple) { recording in
            let kit = try await VoiceModels.shared.transcriber()
            // Without this WhisperKit prefills English and never detects the language.
            let options = DecodingOptions(usePrefillPrompt: false, detectLanguage: true)
            let results = try await kit.transcribe(audioPath: recording.url.path, decodeOptions: options)
            // Whisper marks silence and noise as "[BLANK_AUDIO]" or "(music)": not words.
            return results.map(\.text).joined(separator: " ")
                .replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The language chosen in Settings, or every language of the system (at most three) that Apple knows.
    @MainActor
    static func languages() async -> [Locale] {
        let chosen = AppSettings.shared.transcriptionLanguage
        let wanted = chosen.isEmpty ? Locale.preferredLanguages.map(Locale.init(identifier:)) : [Locale(identifier: chosen)]
        var result: [Locale] = []
        for locale in wanted where result.count < 3 {
            let code = locale.language.languageCode
            guard !result.contains(where: { $0.language.languageCode == code }) else { continue }
            let speech = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            let dictation = await DictationTranscriber.supportedLocale(equivalentTo: locale)
            if speech != nil || dictation != nil {
                result.append(locale)
            }
        }
        return result.isEmpty ? [Locale.current] : result
    }
}

/// One language's recognition, and how sure it was.
struct RecognitionLane {
    struct Score: Sendable {
        var text: String
        /// The sum of the confidences of its characters.
        var confidence: Double
        var characters: Int
    }

    /// The surest text (the longest when no confidences were given); nil when nothing was heard.
    static func best(_ scores: [Score]) -> Score? {
        scores.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .max { a, b in
                let ma = a.characters > 0 ? a.confidence / Double(a.characters) : 0
                let mb = b.characters > 0 ? b.confidence / Double(b.characters) : 0
                return ma == mb ? a.characters < b.characters : ma < mb
            }
    }
}

/// `SpeechAnalyzer` on this Mac, one per language (Apple does not tell languages apart by itself):
/// `SpeechTranscriber` where it knows the language, else `DictationTranscriber` (Russian among its languages).
@MainActor
final class AppleTranscription: TranscriptionSession {
    private let lanes: [Lane]

    private struct Lane {
        let analyzer: SpeechAnalyzer
        let feeder: Feeder
        let results: Task<RecognitionLane.Score, Error>
    }

    private init(lanes: [Lane]) {
        self.lanes = lanes
    }

    static func start(locales: [Locale], onPartial: @escaping @MainActor (String) -> Void,
                      onProgress: @escaping @MainActor (Double?) -> Void) async throws -> AppleTranscription {
        let live = LiveScores(count: locales.count, onPartial: onPartial)
        var lanes: [Lane] = []
        var lastError: Error?
        for (index, locale) in locales.enumerated() {
            do {
                lanes.append(try await lane(locale, index: index, live: live, onProgress: onProgress))
            } catch {
                lastError = error
            }
        }
        guard !lanes.isEmpty else { throw lastError ?? VoiceError.languageUnsupported(locales.first?.identifier ?? "") }
        return AppleTranscription(lanes: lanes)
    }

    private static func lane(_ locale: Locale, index: Int, live: LiveScores,
                             onProgress: @escaping @MainActor (Double?) -> Void) async throws -> Lane {
        let module: any SpeechModule
        let speech: SpeechTranscriber?
        let dictation: DictationTranscriber?
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            speech = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults],
                                       attributeOptions: [.transcriptionConfidence])
            dictation = nil
            module = speech!
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            dictation = DictationTranscriber(locale: supported, contentHints: [], transcriptionOptions: [.punctuation],
                                             reportingOptions: [.volatileResults], attributeOptions: [.transcriptionConfidence])
            speech = nil
            module = dictation!
        } else {
            throw VoiceError.languageUnsupported(locale.identifier)
        }
        let modules = [module]

        if await AssetInventory.status(forModules: modules) != .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            onProgress(0)
            let watch = Task { @MainActor in
                while !Task.isCancelled {
                    onProgress(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { watch.cancel(); onProgress(nil) }
            try await request.downloadAndInstall()
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw VoiceError.engine("Apple recognition has no audio format for \(locale.identifier).")
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let feeder = Feeder(format: format, continuation: continuation)

        // Finished pieces add up; the volatile one is replaced as it is revised.
        let results = Task { @MainActor () throws -> RecognitionLane.Score in
            var final = RecognitionLane.Score(text: "", confidence: 0, characters: 0)
            @MainActor func take(_ text: AttributedString, _ isFinal: Bool) {
                var piece = RecognitionLane.Score(text: String(text.characters), confidence: 0, characters: 0)
                for run in text.runs {
                    let count = text[run.range].characters.count
                    piece.characters += count
                    piece.confidence += (run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] ?? 0) * Double(count)
                }
                let shown = RecognitionLane.Score(text: final.text + piece.text, confidence: final.confidence + piece.confidence,
                                                  characters: final.characters + piece.characters)
                if isFinal { final = shown }
                live.update(index, shown)
            }
            if let speech {
                for try await result in speech.results { take(result.text, result.isFinal) }
            } else if let dictation {
                for try await result in dictation.results { take(result.text, result.isFinal) }
            }
            return final
        }
        let analyzer = SpeechAnalyzer(modules: modules)
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            results.cancel()
            throw VoiceError.engine(error.localizedDescription)
        }
        return Lane(analyzer: analyzer, feeder: feeder, results: results)
    }

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        for lane in lanes { lane.feeder.append(buffer) }
    }

    func finish(_ recording: Recording) async throws -> String {
        var scores: [RecognitionLane.Score] = []
        for lane in lanes {
            lane.feeder.finish()
            try? await lane.analyzer.finalizeAndFinishThroughEndOfInput()
            if let score = try? await lane.results.value { scores.append(score) }
        }
        return RecognitionLane.best(scores)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func cancel() {
        for lane in lanes {
            lane.feeder.finish()
            lane.results.cancel()
            let analyzer = lane.analyzer
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// The live text of every language; the surest one is shown.
    @MainActor
    private final class LiveScores {
        private var scores: [RecognitionLane.Score]
        private let onPartial: @MainActor (String) -> Void

        init(count: Int, onPartial: @escaping @MainActor (String) -> Void) {
            scores = Array(repeating: RecognitionLane.Score(text: "", confidence: 0, characters: 0), count: count)
            self.onPartial = onPartial
        }

        func update(_ index: Int, _ score: RecognitionLane.Score) {
            scores[index] = score
            if let best = RecognitionLane.best(scores) { onPartial(best.text) }
        }
    }

    /// Converts the microphone buffers to the analyzer's format and hands them on; used on the audio thread.
    private final class Feeder: @unchecked Sendable {
        private let lock = NSLock()
        private let format: AVAudioFormat
        private let continuation: AsyncStream<AnalyzerInput>.Continuation
        private var converter: AVAudioConverter?
        private var done = false

        init(format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
            self.format = format
            self.continuation = continuation
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            if buffer.format == format {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            if converter == nil || converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: format)
            }
            guard let converter else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var given = false
            converter.convert(to: converted, error: nil) { _, status in
                if given { status.pointee = .noDataNow; return nil }
                given = true
                status.pointee = .haveData
                return buffer
            }
            if converted.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: converted)) }
        }

        func finish() {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            continuation.finish()
        }
    }
}

/// The final text from Whisper, with Apple's live text meanwhile;
/// Apple's text stands in when it fails or hears nothing.
@MainActor
final class FinalTranscription: TranscriptionSession {
    private let fallback: AppleTranscription?
    private let transcribe: @MainActor (Recording) async throws -> String
    private var task: Task<String, Error>?

    init(fallback: AppleTranscription?, transcribe: @escaping @MainActor (Recording) async throws -> String) {
        self.fallback = fallback
        self.transcribe = transcribe
    }

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        fallback?.append(buffer)
    }

    func finish(_ recording: Recording) async throws -> String {
        let apple = try? await fallback?.finish(recording)
        let transcribe = transcribe
        let task = Task { try await transcribe(recording) }
        self.task = task
        do {
            let text = try await task.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? apple ?? "" : text
        } catch {
            guard let apple, !apple.isEmpty, !Task.isCancelled else { throw error }
            voiceLog.error("transcription failed, Apple's text used: \(error.localizedDescription, privacy: .public)")
            return apple
        }
    }

    func cancel() {
        task?.cancel()
        fallback?.cancel()
    }
}
