import AVFoundation
import Foundation
import Observation

/// The voice loop of the notch: listen until a pause, transcribe, send to the assistant's chat, wait for the
/// answer (and its speech), then keep listening for a while for a follow-up.
@Observable
@MainActor
final class AssistantController {
    static let shared = AssistantController()

    enum Phase: Equatable {
        case idle, listening(followUp: Bool), transcribing, answering, speaking
    }

    private(set) var phase = Phase.idle
    /// What the user said last (live while they speak, with Apple recognition).
    private(set) var heard = ""
    private(set) var error: String?
    private(set) var microphoneDenied = false
    /// Apple's speech model being downloaded, 0…1.
    private(set) var downloadProgress: Double?
    /// An answer finished while the notch was folded.
    private(set) var hasUnreadAnswer = false

    private let settings = AppSettings.shared
    private let recorder = VoiceRecorder.shared
    private var session: (any TranscriptionSession)?
    /// The running conversation (listen → answer → listen again); nil when idle.
    private var cycle: Task<Void, Never>?
    /// Listening for the answer to a question card while the answer waits.
    private var questionListening = false

    private init() {}

    /// The assistant's chat; a new "Assistant" chat when there is none (or it was deleted).
    var chatID: Chat.ID {
        if let id = settings.assistantChatID, ChatStore.shared.chat(id) != nil { return id }
        return newChat()
    }

    private var isExpanded: Bool { NotchPanelController.shared.model.isExpanded }

    var mood: AssistantAvatar.Mood {
        if error != nil { return .error }
        if Speaker.shared.isSpeaking { return .speaking }
        switch phase {
        case .listening: return .listening
        case .transcribing, .answering: return .thinking
        case .speaking: return .speaking
        case .idle: return .idle
        }
    }

    var waveMode: Waveform.Mode {
        if Speaker.shared.isSpeaking { return .output }
        switch phase {
        case .listening: return .input
        case .transcribing, .answering: return .wave
        case .speaking: return .output
        case .idle: return .idle
        }
    }

    var level: Double { Speaker.shared.isSpeaking ? Speaker.shared.level : recorder.level }

    var isBusy: Bool { phase != .idle || Speaker.shared.isSpeaking }

    // MARK: The notch

    /// Keeps the notch's face, bars and size in step with the assistant.
    func attach(_ model: NotchModel) {
        model.onExpand = { [weak self] in self?.expanded() }
        model.onCollapse = { [weak self] in self?.collapsed() }
        model.onAvatarTap = { [weak self] in self?.listen() }
        Task { @MainActor [weak self, weak model] in
            while let self, let model {
                model.mood = mood
                model.wave = waveMode
                model.level = level
                model.isBusy = isBusy
                model.hasUnread = hasUnreadAnswer
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func expanded() {
        hasUnreadAnswer = false
        error = nil
        if !ChatController.shared.isStreaming(chatID) { listen() }
    }

    /// Folding stops listening and speaking; an answer being written goes on.
    func collapsed() {
        recorder.cancel()
        session?.cancel()
        session = nil
        Speaker.shared.stop()
    }

    /// Starts a conversation, unless one is already running.
    func listen() {
        guard cycle == nil else { return }
        error = nil
        cycle = Task { [weak self] in
            await self?.converse()
            self?.cycle = nil
        }
    }

    func stopAll() {
        let id = chatID
        cycle?.cancel()
        collapsed()
        ChatController.shared.stop(id)
        QuestionCenter.shared.dismiss(in: id)
        phase = .idle
    }

    func newConversation() {
        stopAll()
        _ = newChat()
        heard = ""
        error = nil
    }

    /// Reads the last answer aloud, or stops it.
    func speakLastAnswer() {
        guard let message = ChatStore.shared.chat(chatID)?.messages.last(where: { $0.role == .assistant }) else { return }
        if Speaker.shared.speakingID == message.id.uuidString { Speaker.shared.stop(); return }
        let text = SpeechText.plain((message.steps.map(\.text) + [message.content]).filter { !$0.isEmpty }.joined(separator: "\n\n"))
        Task {
            do { try await Speaker.shared.speak(text, id: message.id.uuidString) }
            catch { self.error = error.localizedDescription }
        }
    }

    @discardableResult
    private func newChat() -> Chat.ID {
        let chat = ChatStore.shared.newChat(model: settings.defaultModel)
        ChatStore.shared.update(chat.id) { $0.title = "Assistant" }
        settings.assistantChatID = chat.id
        return chat.id
    }

    // MARK: The loop

    private func converse() async {
        var followUp = false
        defer { if !questionListening { phase = .idle } }
        while !Task.isCancelled {
            guard let text = await hear(followUp: followUp) else { return }
            let id = chatID
            ChatController.shared.send(text, in: id)
            guard ChatController.shared.isStreaming(id) else {
                error = ChatController.shared.errors[id]?.localizedDescription
                return
            }
            phase = .answering
            await waitForAnswer(id)
            if let failure = ChatController.shared.errors[id] {
                error = failure.localizedDescription
                return
            }
            while Speaker.shared.isSpeaking, !Task.isCancelled {
                phase = .speaking
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard isExpanded, !Task.isCancelled else {
                if !isExpanded { hasUnreadAnswer = true }
                return
            }
            followUp = true
        }
    }

    /// Waits for the answer; a question card it shows is answered by voice (the notch opens for it).
    private func waitForAnswer(_ id: Chat.ID) async {
        while ChatController.shared.isStreaming(id), !Task.isCancelled {
            if QuestionCenter.shared.pending[id] != nil, !questionListening, !Speaker.shared.isSpeaking {
                if !isExpanded { NotchPanelController.shared.expand() }
                questionListening = true
                Task { [weak self] in
                    guard let self else { return }
                    if let text = await self.hear(followUp: true), QuestionCenter.shared.pending[id] != nil {
                        QuestionCenter.shared.answer(.one(text), in: id)
                    }
                    self.questionListening = false
                    if ChatController.shared.isStreaming(id) { self.phase = .answering }
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// One phrase as text; nil when nothing was said in time, it was cancelled or it failed (`error`).
    private func hear(followUp: Bool) async -> String? {
        guard await VoiceRecorder.requestAccess() else {
            microphoneDenied = true
            error = VoiceError.microphoneDenied.localizedDescription
            return nil
        }
        microphoneDenied = false
        while !Task.isCancelled {
            do {
                let format = try recorder.inputFormat()
                phase = .listening(followUp: followUp)
                heard = ""
                let session = try await Transcription.start(
                    inputFormat: format,
                    onPartial: { [weak self] text in self?.heard = text },
                    onProgress: { [weak self] progress in self?.downloadProgress = progress })
                self.session = session
                var config = SilenceDetector.Config()
                config.silence = settings.silencePause
                config.wait = followUp ? settings.followUpWindow : settings.speechWait
                guard let recording = try await recorder.record(config, onBuffer: { session.append($0) }) else {
                    session.cancel()
                    self.session = nil
                    return nil
                }
                phase = .transcribing
                defer { try? FileManager.default.removeItem(at: recording.url) }
                let text = try await session.finish(recording)
                self.session = nil
                // Nothing recognised: listen again in the same way.
                guard !text.isEmpty else { continue }
                heard = text
                return text
            } catch {
                session?.cancel()
                session = nil
                self.error = error.localizedDescription
                return nil
            }
        }
        return nil
    }
}
