@preconcurrency import AVFoundation
import Speech

/// Turns one recorded phrase into text: live while it is spoken (Apple) or after it (the API).
@MainActor
protocol TranscriptionSession: AnyObject, Sendable {
    /// Every microphone buffer, on the audio thread.
    nonisolated func append(_ buffer: AVAudioPCMBuffer)
    func finish(_ recording: Recording) async throws -> String
    func cancel()
}

enum Transcription {
    /// A transcription model in Settings goes to `/audio/transcriptions`; else Apple recognition on this Mac.
    @MainActor
    static func start(inputFormat: AVAudioFormat, onPartial: @escaping @MainActor (String) -> Void,
                      onProgress: @escaping @MainActor (Double?) -> Void) async throws -> any TranscriptionSession {
        if AppSettings.shared.endpoint(.transcription) != nil {
            return APITranscription()
        }
        return try await AppleTranscription.start(locale: language, onPartial: onPartial, onProgress: onProgress)
    }

    /// The language of Settings, or the system's.
    @MainActor
    static var language: Locale {
        let id = AppSettings.shared.transcriptionLanguage
        return id.isEmpty ? Locale.current : Locale(identifier: id)
    }
}

/// `SpeechAnalyzer` on this Mac: `SpeechTranscriber` where it knows the language, else `DictationTranscriber`
/// (which knows more of them, Russian among them).
@MainActor
final class AppleTranscription: TranscriptionSession {
    private let analyzer: SpeechAnalyzer
    private let feeder: Feeder
    private let results: Task<String, Error>

    private init(analyzer: SpeechAnalyzer, feeder: Feeder, results: Task<String, Error>) {
        self.analyzer = analyzer
        self.feeder = feeder
        self.results = results
    }

    static func start(locale: Locale, onPartial: @escaping @MainActor (String) -> Void,
                      onProgress: @escaping @MainActor (Double?) -> Void) async throws -> AppleTranscription {
        let module: any SpeechModule
        let speech: SpeechTranscriber?
        let dictation: DictationTranscriber?
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            speech = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
            dictation = nil
            module = speech!
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            dictation = DictationTranscriber(locale: supported, preset: .progressiveShortDictation)
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
            throw VoiceError.engine("Apple recognition has no audio format for this language.")
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let feeder = Feeder(format: format, continuation: continuation)

        // Finished pieces add up; the volatile one is replaced as it is revised.
        let results = Task { @MainActor () throws -> String in
            var final = ""
            @MainActor func show(_ text: AttributedString, _ isFinal: Bool) {
                let piece = String(text.characters)
                if isFinal { final += piece; onPartial(final) } else { onPartial(final + piece) }
            }
            if let speech {
                for try await result in speech.results { show(result.text, result.isFinal) }
            } else if let dictation {
                for try await result in dictation.results { show(result.text, result.isFinal) }
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
        return AppleTranscription(analyzer: analyzer, feeder: feeder, results: results)
    }

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        feeder.append(buffer)
    }

    func finish(_ recording: Recording) async throws -> String {
        feeder.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await results.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        feeder.finish()
        results.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
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

/// The transcription model of Settings, on the chat's server; the phrase is sent once it is over.
@MainActor
final class APITranscription: TranscriptionSession {
    private var task: Task<String, Error>?

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {}

    func finish(_ recording: Recording) async throws -> String {
        guard let endpoint = AppSettings.shared.endpoint(.transcription) else {
            throw APIError(status: nil, message: "The transcription model's address is not valid (Settings → Assistant).", url: nil)
        }
        let wav = try Data(contentsOf: recording.url)
        let client = OpenAIClient(baseURL: endpoint.url, token: endpoint.token)
        let model = endpoint.model
        let language = Transcription.language.language.languageCode?.identifier
        let task = Task { try await client.transcribe(wav: wav, model: model, language: language) }
        self.task = task
        return try await task.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        task?.cancel()
    }
}
