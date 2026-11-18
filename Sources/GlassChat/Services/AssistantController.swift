import AVFoundation
import Foundation
import Observation

/// The voice of the notch, a walkie-talkie: it hears only while the talk shortcut is held (or the pointer rests on
/// the notch); letting go sends what was said (nothing, when nothing was). Two modes: the shortcut opens the notch
/// into the chat; the pointer keeps it compact (the face and the bars) until the model opens it to show something,
/// or the user clicks it.
/// Starting to talk during an answer silences its voice at once; the answer's text goes on until the user speaks.
@Observable
@MainActor
final class AssistantController {
    static let shared = AssistantController()

    enum Phase: Equatable {
        case idle, listening(followUp: Bool), transcribing, answering, speaking
    }

    /// Listening while the shortcut is held, then transcribing; otherwise what the answer is doing.
    var phase: Phase {
        if listening { return .listening(followUp: false) }
        if transcribing { return .transcribing }
        if let id = settings.assistantChatID, ChatController.shared.isStreaming(id) { return .answering }
        if Speaker.shared.isSpeaking { return .speaking }
        return .idle
    }
    /// What the user said last (live while they speak, with Apple recognition).
    private(set) var heard = ""
    private(set) var error: String?
    private(set) var microphoneDenied = false
    /// Apple's speech model being downloaded, 0…1.
    private(set) var downloadProgress: Double?
    /// An answer finished while the notch was folded.
    private(set) var hasUnreadAnswer = false
    /// The user started talking again: the answer going on says nothing more aloud (app_say), until the next message.
    private(set) var hushed = false

    /// What holds the phrase: the talk shortcut, or the pointer resting on the folded notch.
    enum TalkSource: Equatable { case key, hover }
    private var talkSource: TalkSource?
    /// The pointer came onto the folded notch; it talks after a moment (passing over it does not).
    private var hoverWait: Task<Void, Never>?
    /// How long the pointer rests on the notch before it listens.
    static let hoverDelay: Duration = .milliseconds(250)
    /// When the phrase was let go, to log how long sending it took.
    private var releasedAt: Date?

    private let settings = AppSettings.shared
    private let recorder = VoiceRecorder.shared
    private var session: (any TranscriptionSession)?
    /// The phrase held now (recording, then transcribing and sending); nil when the shortcut is not held.
    private var talk: Task<Void, Never>?
    /// Which phrase is the current one: a cancelled one finishing late must not touch the next.
    private var talkID = UUID()
    private var listening = false
    private var transcribing = false
    /// Follows the answer being written: opens the notch for its cards, marks it unread, shows its error.
    private var answerWatch: Task<Void, Never>?

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

    var waveMode: Waveform.Mode { Self.waveMode(for: phase, speaking: Speaker.shared.isSpeaking) }

    /// The bars: the voice while listening, the speech while speaking, the flowing wave only while the answer is
    /// being thought out (still while transcribing, so they never look busy for nothing).
    static func waveMode(for phase: Phase, speaking: Bool) -> Waveform.Mode {
        if speaking { return .output }
        switch phase {
        case .listening: return .input
        case .answering: return .wave
        case .speaking: return .output
        case .transcribing, .idle: return .idle
        }
    }

    var level: Double { Speaker.shared.isSpeaking ? Speaker.shared.level : recorder.level }

    /// From the moment the shortcut is pressed (it may still be asking for the microphone) until the answer is over.
    var isBusy: Bool { talk != nil || phase != .idle }

    // MARK: The notch

    /// Keeps the notch's face, bars and size in step with the assistant.
    func attach(_ model: NotchModel) {
        model.onExpand = { [weak self] in self?.expanded() }
        model.onCollapse = { [weak self] in self?.collapsed() }
        model.onPointer = { [weak self] inside in self?.pointer(onNotch: inside) }
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

    /// Opening the notch shows the conversation; it does not listen (the shortcut and the pointer do).
    /// A click while the pointer was talking ends that phrase: what was said is sent.
    func expanded() {
        voiceLog.debug("notch expanded")
        prewarm()
        hasUnreadAnswer = false
        error = nil
        hoverWait?.cancel()
        hoverWait = nil
        if talkSource == .hover { talkReleased(.hover) }
    }

    /// Folding drops the phrase being held and stops speaking; an answer being written goes on.
    func collapsed() {
        voiceLog.debug("notch collapsed")
        cancelTalk()
        if !foldingBack { Speaker.shared.stop() }
    }

    /// Folding a notch that opened only for a phrase: the answer it found going on keeps its voice.
    private var foldingBack = false

    private func foldBack() {
        foldingBack = true
        NotchPanelController.shared.collapse()
        foldingBack = false
    }

    /// The shortcut opened the notch, and nothing was said: it folds again.
    private var foldsBack: Bool {
        isExpanded && PushToTalk.foldsBack(openedByPress: openedByPress, outcome: .discard)
    }

    /// The notch was folded when the shortcut went down (and the shortcut opened it).
    private var openedByPress = false

    /// Local Whisper loads its model before it is needed: loading it when the phrase is over takes seconds.
    func prewarm() {
        guard settings.recognitionMode == .whisper, VoiceModels.shared.whisper == .ready else { return }
        Task { _ = try? await VoiceModels.shared.transcriber() }
    }

    /// The model asked to show what it writes: the compact notch opens (without taking the keyboard).
    func expandForAnswer() {
        guard !isExpanded else { return }
        voiceLog.debug("the model opens the notch")
        NotchPanelController.shared.expand(focus: false)
    }

    /// Where the assistant is seen when a phrase is sent: the compact notch, or the open one.
    private var surface: AssistantPrompt.Surface { isExpanded ? .expandedNotch : .notch }

    func stopAll() {
        voiceLog.debug("stop all")
        let id = chatID
        answerWatch?.cancel()
        answerWatch = nil
        collapsed()
        ChatController.shared.stop(id)
        QuestionCenter.shared.dismiss(in: id)
        ApprovalCenter.shared.dismiss(in: id)
    }

    /// A new chat; the notch stays open for the next phrase.
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
            // Through the echo canceller: the user may hold the shortcut and talk over it.
            do { try await Speaker.shared.speak(text, id: message.id.uuidString, interruptible: true) }
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

    // MARK: The shortcut and the pointer

    /// The pointer came onto the notch or left it. Resting on the folded notch talks as the shortcut does;
    /// leaving it sends the phrase.
    private func pointer(onNotch inside: Bool) {
        hoverWait?.cancel()
        hoverWait = nil
        guard inside else {
            if talkSource == .hover { talkReleased(.hover) }
            return
        }
        guard settings.hoverToTalk, !isExpanded, talk == nil else { return }
        hoverWait = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverDelay)
            guard let self, !Task.isCancelled, !self.isExpanded else { return }
            self.hoverWait = nil
            self.talkPressed(.hover)
        }
    }

    /// The shortcut went down (or the pointer rests on the notch): it listens until it is let go. The shortcut opens
    /// the notch into the chat; the pointer keeps it compact. The answer's voice stops at once.
    func talkPressed(_ source: TalkSource = .key) {
        guard talk == nil else { return }
        voiceLog.debug("talk pressed (\(String(describing: source), privacy: .public))")
        talkSource = source
        openedByPress = source == .key && !isExpanded
        if openedByPress { NotchPanelController.shared.expand(focus: false) }
        releasedAt = nil
        prewarm()
        let chat = chatID
        // Talking again silences every app_say of the answer going on; its text goes on until the user speaks.
        if stillAnswering(chat) {
            hushed = true
            Speaker.shared.stop()
        }
        error = nil
        let id = UUID()
        talkID = id
        talk = Task { [weak self] in
            await self?.hold(chat: chat)
            if self?.talkID == id {
                self?.talk = nil
                self?.talkSource = nil
            }
        }
    }

    /// The shortcut was let go (or the pointer left the notch): the phrase is over. Only what started it ends it.
    func talkReleased(_ source: TalkSource = .key) {
        guard talk != nil, talkSource == source else { return }
        voiceLog.debug("talk released (\(String(describing: source), privacy: .public))")
        releasedAt = .now
        released = true
        recorder.finish()
    }

    /// Another key came with the shortcut (another shortcut), Esc, or the notch folded: nothing is sent.
    func talkCancelled(_ source: TalkSource? = nil) {
        guard talk != nil, source == nil || talkSource == source else { return }
        voiceLog.debug("talk cancelled")
        let folds = foldsBack
        cancelTalk()
        if folds { foldBack() }
    }

    private func cancelTalk() {
        hoverWait?.cancel()
        hoverWait = nil
        talk?.cancel()
        talk = nil
        talkSource = nil
        talkID = UUID()
        recorder.cancel()
        session?.cancel()
        session = nil
        listening = false
        transcribing = false
        released = false
    }

    // MARK: Holding

    /// The shortcut was let go before the recording started: nothing will end it, so it must not start.
    private var released = false
    /// The user started talking over the answer (it was stopped).
    private var interrupted = false
    /// What was heard, one utterance at a time (during an answer: the echo before the user's words is not theirs).
    private var utterance = BargeIn.Utterance()
    /// Where the user's phrase starts in the recording during an answer (Whisper hears only that part).
    private var phraseStart: TimeInterval = 0

    /// Records while the shortcut is held, then sends what was said: a new message, or the answer to a question card.
    private func hold(chat: Chat.ID) async {
        released = false
        interrupted = false
        utterance = BargeIn.Utterance()
        phraseStart = 0
        // An answer being written or spoken goes on until the user talks; a question card waits for its answer.
        let answering = ChatController.shared.isStreaming(chat) || Speaker.shared.isSpeaking
        let question = QuestionCenter.shared.pending[chat] != nil
        if !answering { heard = "" }

        let allowed = await VoiceRecorder.requestAccess()
        guard !Task.isCancelled else { return }
        guard allowed else {
            microphoneDenied = true
            error = VoiceError.microphoneDenied.localizedDescription
            return
        }
        microphoneDenied = false
        guard !released else { return finishSilently() }
        do {
            AudioEngineHub.shared.configure()
            let format = try recorder.inputFormat()
            let session = try await Transcription.start(
                inputFormat: format,
                onPartial: { [weak self] text in self?.partial(text, chat: chat, answering: answering, question: question) },
                onProgress: { [weak self] progress in self?.downloadProgress = progress })
            guard !Task.isCancelled else {
                session.cancel()
                return
            }
            self.session = session
            guard !released else {
                session.cancel()
                self.session = nil
                return finishSilently()
            }
            listening = true
            // No pause and no limit ends it: letting go of the shortcut does (`finish`).
            var config = SilenceDetector.Config()
            config.silence = .infinity
            config.wait = .infinity
            config.maxPhrase = .infinity
            let recording = try await recorder.record(config, onBuffer: { session.append($0) })
            listening = false
            guard let recording, !Task.isCancelled else {
                session.cancel()
                self.session = nil
                return
            }
            voiceLog.debug("held phrase, duration \(recording.duration), voiced \(recording.voiced)")
            guard recording.voiced >= SilenceDetector.minimumVoiced else {
                session.cancel()
                self.session = nil
                try? FileManager.default.removeItem(at: recording.url)
                return finishSilently()
            }
            let text = try await transcribe(recording, with: session, answering: answering && !question)
            guard !Task.isCancelled else { return }
            // Apple heard the whole recording: during an answer only the last utterance is the user's (what came
            // before a pause was the assistant's voice or the room). Whisper heard only their part once they interrupted.
            let words = answering && !question && (!interrupted || settings.recognitionMode != .whisper) ? utterance.words(of: text) : text
            guard PushToTalk.outcome(voiced: recording.voiced, text: words) == .send else { return finishSilently() }
            if answering, !question, !interrupted {
                // Words that came only as it was let go: an interruption if they are not the assistant's own voice.
                guard !stillAnswering(chat) || BargeIn.isMeaningful(heard: words, voiced: recording.voiced, spoken: Speaker.shared.spoken)
                else { return finishSilently() }
                interrupt(chat)
            }
            heard = words
            await send(words, chat: chat, question: question)
        } catch {
            listening = false
            transcribing = false
            session?.cancel()
            session = nil
            if Task.isCancelled || error is CancellationError { return }
            voiceLog.error("hold failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    /// Nothing was said: nothing is sent, and a notch the shortcut opened only for this folds again.
    private func finishSilently() {
        voiceLog.debug("nothing said: nothing sent")
        listening = false
        transcribing = false
        if foldsBack {
            // Folding cancels the phrase; this one is over already.
            talk = nil
            talkSource = nil
            talkID = UUID()
            foldBack()
        }
    }

    private func stillAnswering(_ chat: Chat.ID) -> Bool {
        ChatController.shared.isStreaming(chat) || Speaker.shared.isSpeaking
    }

    /// Live words while the shortcut is held. During an answer the first meaningful ones (not the assistant's own
    /// voice) stop it; before that the answer goes on and nothing is shown.
    private func partial(_ text: String, chat: Chat.ID, answering: Bool, question: Bool) {
        guard answering else {
            heard = text
            return
        }
        let now = utterance.update(text, voiced: recorder.voiced, at: recorder.elapsed)
        // The answer ended while the shortcut is held: the words are the user's to see.
        if !question, !interrupted, !stillAnswering(chat) {
            heard = now.text
            return
        }
        if interrupted || question {
            if question, !interrupted, BargeIn.isMeaningful(heard: now.text, voiced: now.voiced, spoken: Speaker.shared.spoken) {
                // Answering the question out loud: its voice stops, the answer waits for the card.
                interrupted = true
                Speaker.shared.stop()
            }
            if interrupted { heard = question ? text : now.text }
            return
        }
        guard stillAnswering(chat), BargeIn.isMeaningful(heard: now.text, voiced: now.voiced, spoken: Speaker.shared.spoken) else { return }
        voiceLog.debug("barge-in: \(now.text, privacy: .public)")
        phraseStart = max(utterance.start - 1.5, 0)
        interrupt(chat)
        heard = now.text
    }

    /// The user talks over the answer: it stops, with its voice and its cards.
    private func interrupt(_ chat: Chat.ID) {
        interrupted = true
        Speaker.shared.stop()
        ChatController.shared.stop(chat)
        ApprovalCenter.shared.dismiss(in: chat)
        QuestionCenter.shared.dismiss(in: chat)
    }

    /// The phrase goes to the question card waiting for it, or to the chat as the next message.
    private func send(_ text: String, chat: Chat.ID, question: Bool) async {
        if question, QuestionCenter.shared.pending[chat] != nil {
            QuestionCenter.shared.answer(.one(text), in: chat)
            return
        }
        // A stopped answer saves what it wrote first.
        while ChatController.shared.isStreaming(chat), !Task.isCancelled { try? await Task.sleep(for: .milliseconds(30)) }
        guard !Task.isCancelled else { return }
        // The answer it interrupted is over (its watcher has seen it stop): errors of the next one count again.
        interrupted = false
        hushed = false
        Speaker.shared.resetSpoken()
        let surface = surface
        ChatController.shared.send(text, in: chat, surface: surface)
        if let releasedAt {
            voiceLog.debug("sent \(Date.now.timeIntervalSince(releasedAt), format: .fixed(precision: 2))s after letting go")
            self.releasedAt = nil
        }
        guard ChatController.shared.isStreaming(chat) else {
            error = ChatController.shared.errors[chat]?.localizedDescription
            return
        }
        watchAnswer(chat, surface: surface)
    }

    /// Follows the answer until it is written and spoken. One heard in the compact notch is not left unread:
    /// only one the user folded away while reading it is.
    private func watchAnswer(_ chat: Chat.ID, surface: AssistantPrompt.Surface) {
        answerWatch?.cancel()
        answerWatch = Task { [weak self] in
            // Opened during the answer (the model showed something, or the user clicked): it is there to be read.
            var shownDuring = false
            while ChatController.shared.isStreaming(chat), !Task.isCancelled {
                if self?.isExpanded == true { shownDuring = true }
                // An action to allow or a question to answer: the notch opens for its card.
                if ApprovalCenter.shared.pending[chat] != nil || QuestionCenter.shared.pending[chat] != nil,
                   self?.isExpanded == false {
                    NotchPanelController.shared.expand()
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, !Task.isCancelled else { return }
            // Stopped by the user talking over it: not an error.
            if let failure = ChatController.shared.errors[chat], !interrupted {
                error = failure.localizedDescription
            }
            if !isExpanded, surface == .expandedNotch || shownDuring { hasUnreadAnswer = true }
        }
    }

    /// The text of a recorded phrase. During an answer, once the user interrupted, Whisper gets only their part.
    private func transcribe(_ recording: Recording, with session: any TranscriptionSession, answering: Bool) async throws -> String {
        transcribing = true
        defer { transcribing = false }
        var recording = recording
        if answering, interrupted, settings.recognitionMode == .whisper {
            recording = VoiceRecorder.trimmed(recording, from: phraseStart)
        }
        defer { try? FileManager.default.removeItem(at: recording.url) }
        let text = try await session.finish(recording)
        self.session = nil
        voiceLog.debug("transcribed: \(text, privacy: .public)")
        // Apple alone: a noise phrase from a short burst ("Thank you." for a cough) is not sent.
        if settings.recognitionMode == .builtIn, recording.voiced < 1.5, WhisperFilter.isNoise(text) {
            voiceLog.debug("dropped as noise: \(text, privacy: .public)")
            return ""
        }
        return text
    }
}
