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

    private(set) var phase = Phase.idle { didSet { voiceLog.debug("phase \(String(describing: self.phase), privacy: .public)") } }
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
    /// Which conversation is the current one: a cancelled one finishing late must not touch the next.
    private var cycleID = UUID()
    /// Listening for the answer to a question card while the answer waits.
    private var questionListening = false
    /// Recording while the pointer rests on the folded notch.
    private var hoverTalking = false

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

    /// From the moment a conversation starts (it may still be asking for the microphone) until it is over.
    var isBusy: Bool { cycle != nil || phase != .idle || Speaker.shared.isSpeaking }

    // MARK: The notch

    /// Keeps the notch's face, bars and size in step with the assistant.
    func attach(_ model: NotchModel) {
        model.onExpand = { [weak self] in self?.expanded() }
        model.onCollapse = { [weak self] in self?.collapsed() }
        model.onAvatarTap = { [weak self] in self?.listen() }
        model.onHoverTalk = { [weak self] in self?.hoverStarted() }
        model.onHoverEnd = { [weak self] in self?.hoverEnded() }
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
        voiceLog.debug("notch expanded")
        // Local Whisper loads its model while the user starts talking.
        if settings.recognitionMode == .localWhisper { Task { await LocalWhisper.shared.warmUp() } }
        hasUnreadAnswer = false
        error = nil
        if !ChatController.shared.isStreaming(chatID) { listen() }
    }

    /// Folding stops listening and speaking; an answer being written goes on.
    func collapsed() {
        voiceLog.debug("notch collapsed")
        // A conversation still waiting to listen ends; one with an answer on the way goes on.
        if phase != .answering, phase != .speaking, !questionListening { cycle?.cancel() }
        recorder.cancel()
        session?.cancel()
        session = nil
        Speaker.shared.stop()
    }

    /// Starts a conversation, unless one is already running.
    func listen() {
        voiceLog.debug("listen requested, running: \(self.cycle != nil)")
        guard cycle == nil else { return }
        error = nil
        let id = UUID()
        cycleID = id
        cycle = Task { [weak self] in
            await self?.converse(id)
            if self?.cycleID == id { self?.cycle = nil }
        }
    }

    /// The pointer rests on the folded notch: record until it leaves.
    func hoverStarted() {
        guard cycle == nil, !isExpanded else { return }
        voiceLog.debug("hover talk started")
        error = nil
        let id = UUID()
        cycleID = id
        hoverTalking = true
        cycle = Task { [weak self] in
            guard let self else { return }
            let first = await self.hearWhileHovering()
            self.hoverTalking = false
            if let first {
                await self.converse(id, first: first)
            } else if self.cycleID == id {
                self.phase = .idle
            }
            if self.cycleID == id { self.cycle = nil }
        }
    }

    /// The pointer left the notch: the phrase is over.
    func hoverEnded() {
        guard hoverTalking else { return }
        voiceLog.debug("hover talk ended")
        // Before the recording started, this keeps it from starting (nothing would end it).
        hoverTalking = false
        recorder.finish()
    }

    func stopAll() {
        voiceLog.debug("stop all")
        let id = chatID
        cycle?.cancel()
        cycle = nil
        cycleID = UUID()
        collapsed()
        ChatController.shared.stop(id)
        QuestionCenter.shared.dismiss(in: id)
        phase = .idle
    }

    /// A new chat, and the notch goes on listening in it.
    func newConversation() {
        stopAll()
        _ = newChat()
        heard = ""
        error = nil
        if isExpanded { listen() }
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

    /// `first`: a phrase already heard (by hovering) to send before listening.
    private func converse(_ id: UUID, first: Heard? = nil) async {
        var followUp = false
        var pending = first
        defer { if !questionListening, cycleID == id { phase = .idle } }
        while !Task.isCancelled {
            let heard: Heard
            if let phrase = pending {
                heard = phrase
                pending = nil
            } else {
                guard let phrase = await hear(followUp: followUp) else { return }
                heard = phrase
            }
            let id = chatID
            // With "Audio to the Model" the recording is the message; the words are only shown.
            if let audio = heard.audio {
                ChatController.shared.send("", attachments: [audio], in: id)
            } else {
                ChatController.shared.send(heard.text, in: id)
            }
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
            // 0 s in Settings: no listening after an answer.
            guard settings.followUpWindow > 0 else { return }
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
                    if let heard = await self.hear(followUp: true), !heard.text.isEmpty, QuestionCenter.shared.pending[id] != nil {
                        QuestionCenter.shared.answer(.one(heard.text), in: id)
                    }
                    self.questionListening = false
                    if ChatController.shared.isStreaming(id) { self.phase = .answering }
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// What a phrase gave: its text, and the recording itself with "Audio to the Model".
    private struct Heard {
        let text: String
        let audio: Attachment?
    }

    /// The text of a recorded phrase (and the recording itself with "Audio to the Model"); nil without words.
    private func transcribe(_ recording: Recording, with session: any TranscriptionSession) async throws -> Heard? {
        phase = .transcribing
        defer { try? FileManager.default.removeItem(at: recording.url) }
        let text = try await session.finish(recording)
        self.session = nil
        guard !Task.isCancelled else { return nil }
        voiceLog.debug("transcribed: \(text, privacy: .public)")
        if settings.recognitionMode == .audioToModel {
            heard = text
            return Heard(text: text, audio: try AttachmentStore.importFile(at: recording.url))
        }
        guard SpeechText.isWords(text) else { return nil }
        heard = text
        return Heard(text: text, audio: nil)
    }

    /// Records while the pointer rests on the notch; when it leaves, opens the notch with what was said,
    /// or drops the recording when nothing was.
    private func hearWhileHovering() async -> Heard? {
        let allowed = await VoiceRecorder.requestAccess()
        guard allowed, !Task.isCancelled else {
            if !allowed { microphoneDenied = true }
            return nil
        }
        do {
            let format = try recorder.inputFormat()
            phase = .listening(followUp: false)
            heard = ""
            let session = try await Transcription.start(
                inputFormat: format,
                onPartial: { [weak self] text in self?.heard = text },
                onProgress: { [weak self] progress in self?.downloadProgress = progress })
            guard !Task.isCancelled, hoverTalking else {
                session.cancel()
                return nil
            }
            self.session = session
            // No pause ends it: the pointer leaving does (`finish`).
            var config = SilenceDetector.Config()
            config.silence = .infinity
            config.wait = .infinity
            guard let recording = try await recorder.record(config, onBuffer: { session.append($0) }) else {
                session.cancel()
                self.session = nil
                return nil
            }
            guard HoverTalk.outcome(voiced: recording.voiced) == .open else {
                voiceLog.debug("hover talk dropped, voiced \(recording.voiced)")
                session.cancel()
                self.session = nil
                try? FileManager.default.removeItem(at: recording.url)
                return nil
            }
            NotchPanelController.shared.expand()
            return try await transcribe(recording, with: session)
        } catch {
            session?.cancel()
            session = nil
            if !(Task.isCancelled || error is CancellationError) { self.error = error.localizedDescription }
            return nil
        }
    }

    /// One phrase; nil when nothing was said in time, it was cancelled or it failed (`error`).
    private func hear(followUp: Bool) async -> Heard? {
        let allowed = await VoiceRecorder.requestAccess()
        guard !Task.isCancelled else { return nil }
        guard allowed else {
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
                    onPartial: { [weak self] text in voiceLog.debug("partial: \(text, privacy: .public)"); self?.heard = text },
                    onProgress: { [weak self] progress in self?.downloadProgress = progress })
                guard !Task.isCancelled else {
                    session.cancel()
                    return nil
                }
                self.session = session
                var config = SilenceDetector.Config()
                config.silence = settings.silencePause
                config.wait = followUp ? settings.followUpWindow : settings.speechWait
                guard let recording = try await recorder.record(config, onBuffer: { session.append($0) }) else {
                    session.cancel()
                    self.session = nil
                    return nil
                }
                voiceLog.debug("phrase ended, duration \(recording.duration), voiced \(recording.voiced)")
                // A burst of noise: recognisers would make "Thank you." or "." of it. While waiting for a follow-up
                // it ends the wait; after a click it is ignored.
                if recording.voiced < SilenceDetector.minimumVoiced {
                    session.cancel()
                    self.session = nil
                    try? FileManager.default.removeItem(at: recording.url)
                    if followUp { return nil } else { continue }
                }
                guard let phrase = try await transcribe(recording, with: session) else {
                    guard !Task.isCancelled else { return nil }
                    // Nothing recognised (or only punctuation): listen again in the same way.
                    if followUp { return nil } else { continue }
                }
                return phrase
            } catch {
                if Task.isCancelled || error is CancellationError {
                    session?.cancel()
                    session = nil
                    return nil
                }
                voiceLog.error("hear failed: \(error.localizedDescription, privacy: .public)")
                session?.cancel()
                session = nil
                self.error = error.localizedDescription
                return nil
            }
        }
        return nil
    }
}
