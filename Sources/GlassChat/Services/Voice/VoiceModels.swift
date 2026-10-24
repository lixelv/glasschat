import Foundation
import NaturalLanguage
import Observation
@preconcurrency import Supertonic
@preconcurrency import WhisperKit

/// The two local voice models: whisper-large-v3-turbo (WhisperKit, CoreML) hears, Supertonic 3 (ONNX) speaks.
/// Both are downloaded once into Application Support and kept loaded.
@Observable
@MainActor
final class VoiceModels {
    static let shared = VoiceModels()

    enum State: Equatable {
        case missing
        case downloading(Double)
        case ready
        case failed(String)
    }

    /// The model the app uses; it is not chosen in Settings.
    static let whisperVariant = "openai_whisper-large-v3-v20240930_turbo_632MB"

    private(set) var whisper = State.missing
    private(set) var speech = State.missing

    private var whisperKit: WhisperKit?
    private var whisperLoading: Task<WhisperKit, Error>?
    private var supertonic: Supertonic?
    private var downloading = false

    private static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "GlassChat/models", directoryHint: .isDirectory)
    }
    private static var whisperBase: URL { folder.appending(path: "whisper", directoryHint: .isDirectory) }
    private static var supertonicFolder: URL { folder.appending(path: "supertonic", directoryHint: .isDirectory) }
    private static var whisperMarker: URL { whisperBase.appending(path: "folder.txt") }

    private init() {
        whisper = whisperFolder != nil ? .ready : .missing
        speech = ModelAssets(directory: Self.supertonicFolder).isComplete ? .ready : .missing
    }

    var isComplete: Bool { whisper == .ready && speech == .ready }

    /// Where the downloaded Whisper model is, remembered after its download.
    private var whisperFolder: URL? {
        guard let path = try? String(contentsOf: Self.whisperMarker, encoding: .utf8) else { return nil }
        let url = URL(filePath: path.trimmingCharacters(in: .whitespacesAndNewlines), directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Downloads what is missing (both at once); a failure is shown on that model and can be retried.
    func downloadAll() async {
        guard !downloading else { return }
        downloading = true
        defer { downloading = false }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        async let hearing: Void = downloadWhisper()
        async let speaking: Void = downloadSupertonic()
        _ = await (hearing, speaking)
    }

    private func downloadWhisper() async {
        guard whisper != .ready else { return }
        whisper = .downloading(0)
        do {
            let url = try await WhisperKit.download(variant: Self.whisperVariant, downloadBase: Self.whisperBase,
                                                    progressCallback: Self.whisperProgress())
            try url.path.write(to: Self.whisperMarker, atomically: true, encoding: .utf8)
            whisper = .ready
        } catch {
            whisper = .failed(error.localizedDescription)
        }
    }

    /// Made outside the main actor: the download calls it on its own thread.
    private nonisolated static func whisperProgress() -> @Sendable (Progress) -> Void {
        { progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in VoiceModels.shared.whisper = .downloading(fraction) }
        }
    }

    private func downloadSupertonic() async {
        guard speech != .ready else { return }
        speech = .downloading(0)
        do {
            _ = try await ModelAssets.download(to: Self.supertonicFolder) { progress in
                let fraction = progress.totalBytes > 0 ? Double(progress.downloadedBytes) / Double(progress.totalBytes) : 0
                Task { @MainActor in VoiceModels.shared.speech = .downloading(fraction) }
            }
            speech = .ready
        } catch {
            speech = .failed(error.localizedDescription)
        }
    }

    /// WhisperKit with the downloaded model, loaded once (it takes a few seconds the first time).
    func transcriber() async throws -> WhisperKit {
        if let whisperKit { return whisperKit }
        if let whisperLoading { return try await whisperLoading.value }
        guard whisper == .ready, let folder = whisperFolder else {
            throw MCPError(message: "The Whisper model is not downloaded yet.")
        }
        let task = Task { @MainActor in
            try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, verbose: false, logLevel: .error, prewarm: true, load: true, download: false))
        }
        whisperLoading = task
        defer { whisperLoading = nil }
        let kit = try await task.value
        whisperKit = kit
        return kit
    }

    /// Supertonic with the downloaded model.
    func synthesizer() throws -> Supertonic {
        if let supertonic { return supertonic }
        guard speech == .ready else { throw MCPError(message: "The Supertonic model is not downloaded yet.") }
        let made = try Supertonic(assets: ModelAssets(directory: Self.supertonicFolder))
        supertonic = made
        return made
    }
}

/// The language Supertonic reads a text in, from the text itself.
enum SupertonicLanguage {
    static func language(for text: String) -> SynthesisLanguage {
        guard let code = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue,
              let language = SynthesisLanguage(languageCode: code) else { return .unspecified }
        return language
    }
}

/// One phrase at a time goes through it (the assistant hears one phrase, then the next).
extension WhisperKit: @retroactive @unchecked Sendable {}
