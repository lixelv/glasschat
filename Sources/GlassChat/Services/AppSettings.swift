import Foundation
import Observation

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()
    static let defaultBaseURL = "https://api.openai.com/v1"

    private let defaults = UserDefaults.standard

    var baseURL: String { didSet { defaults.set(baseURL, forKey: "baseURL") } }
    /// The default model's provider (its address is `baseURL`, its token `token`).
    var chatProvider: ModelProvider { didSet { defaults.set(chatProvider.rawValue, forKey: "chatProvider") } }
    var defaultModel: String { didSet { defaults.set(defaultModel, forKey: "defaultModel") } }
    var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: "systemPrompt") } }
    var token: String { didSet { Keychain.setToken(token) } }

    /// Tool groups switched off (MCP server names, `AppTool.key`): one choice for every chat.
    var disabledTools: Set<String> { didSet { defaults.set(Array(disabledTools), forKey: "disabledTools") } }

    /// How many tools a search hands to the model.
    var decisionTopN: Int { didSet { defaults.set(decisionTopN, forKey: "decisionTopN") } }
    /// The models besides the default one: the decision model that ranks tools for `search_tools` (e.g. Jev),
    /// transcription (`/audio/transcriptions`) and speech (`/audio/speech`). No model: their fallback.
    var decisionConnection: ModelConnection { didSet { save(decisionConnection, .decision) } }
    var transcriptionConnection: ModelConnection { didSet { save(transcriptionConnection, .transcription) } }
    var speechConnection: ModelConnection { didSet { save(speechConnection, .speech) } }
    var recognitionMode: RecognitionMode { didSet { defaults.set(recognitionMode.rawValue, forKey: "recognitionMode") } }

    // MARK: Notch assistant

    var assistantEnabled: Bool { didSet { defaults.set(assistantEnabled, forKey: "assistantEnabled") } }
    /// Resting the pointer on the folded notch records until it leaves.
    var hoverToTalk: Bool { didSet { defaults.set(hoverToTalk, forKey: "hoverToTalk") } }
    /// Seconds the pointer rests on the notch before it records.
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    /// The shortcut that opens the notch from any app; nil: none.
    var assistantShortcut: Shortcut? {
        didSet {
            if let assistantShortcut { defaults.set(try? JSONEncoder().encode(assistantShortcut), forKey: "assistantShortcut") }
            else { defaults.set("off", forKey: "assistantShortcut") }
        }
    }
    /// A locale identifier for Apple recognition; empty: the system's.
    var transcriptionLanguage: String { didSet { defaults.set(transcriptionLanguage, forKey: "transcriptionLanguage") } }
    /// Seconds of silence that end a phrase.
    var silencePause: Double { didSet { defaults.set(silencePause, forKey: "silencePause") } }
    /// Seconds the assistant keeps listening after an answer.
    var followUpWindow: Double { didSet { defaults.set(followUpWindow, forKey: "followUpWindow") } }
    /// Seconds it waits for speech after a click.
    var speechWait: Double { didSet { defaults.set(speechWait, forKey: "speechWait") } }
    /// Messages of the assistant chat sent to the model; 0: all.
    var assistantContextLimit: Int { didSet { defaults.set(assistantContextLimit, forKey: "assistantContextLimit") } }
    /// An `AVSpeechSynthesisVoice` identifier; empty: the voice of the system language.
    var systemVoice: String { didSet { defaults.set(systemVoice, forKey: "systemVoice") } }
    var ttsVoice: String { didSet { defaults.set(ttsVoice, forKey: "ttsVoice") } }
    /// Empty: `AssistantPrompt.standard`.
    var assistantPrompt: String { didSet { defaults.set(assistantPrompt, forKey: "assistantPrompt") } }
    var assistantChatID: Chat.ID? { didSet { defaults.set(assistantChatID?.uuidString, forKey: "assistantChatID") } }

    private init() {
        baseURL = defaults.string(forKey: "baseURL") ?? Self.defaultBaseURL
        defaultModel = defaults.string(forKey: "defaultModel") ?? ""
        systemPrompt = defaults.string(forKey: "systemPrompt") ?? ""
        token = Keychain.token() ?? ""
        disabledTools = Set(defaults.stringArray(forKey: "disabledTools") ?? [])
        decisionTopN = defaults.object(forKey: "decisionTopN") as? Int ?? 4
        chatProvider = defaults.string(forKey: "chatProvider").flatMap(ModelProvider.init(rawValue:))
            ?? ModelProvider.detect(defaults.string(forKey: "baseURL") ?? Self.defaultBaseURL)
        // Saved before connections existed: the decision model had its own (or the chat's) address and token,
        // the audio models used the chat's.
        let oldDecisionURL = defaults.string(forKey: "decisionBaseURL") ?? ""
        decisionConnection = Self.load(.decision) ?? ModelConnection(
            provider: ModelProvider.detect(oldDecisionURL), baseURL: oldDecisionURL,
            model: defaults.string(forKey: "decisionModel") ?? "",
            sameAsDefault: oldDecisionURL.isEmpty && (Keychain.token(Keychain.decisionAccount) ?? "").isEmpty)
        let transcription = Self.load(.transcription) ?? ModelConnection(
            provider: .openAI, baseURL: "", model: defaults.string(forKey: "transcriptionModel") ?? "", sameAsDefault: true)
        transcriptionConnection = transcription
        speechConnection = Self.load(.speech) ?? ModelConnection(
            provider: .openAI, baseURL: "", model: defaults.string(forKey: "ttsModel") ?? "", sameAsDefault: true)
        recognitionMode = defaults.string(forKey: "recognitionMode").flatMap(RecognitionMode.init(rawValue:))
            ?? (transcription.model.isEmpty ? .default : .provider)
        assistantEnabled = defaults.object(forKey: "assistantEnabled") as? Bool ?? true
        hoverToTalk = defaults.object(forKey: "hoverToTalk") as? Bool ?? true
        hoverDelay = defaults.object(forKey: "hoverDelay") as? Double ?? 0.3
        switch defaults.object(forKey: "assistantShortcut") {
        case let data as Data: assistantShortcut = (try? JSONDecoder().decode(Shortcut.self, from: data)) ?? .standard
        case "off" as String: assistantShortcut = nil
        default: assistantShortcut = .standard
        }
        transcriptionLanguage = defaults.string(forKey: "transcriptionLanguage") ?? ""
        silencePause = defaults.object(forKey: "silencePause") as? Double ?? 1.5
        followUpWindow = defaults.object(forKey: "followUpWindow") as? Double ?? 15
        speechWait = defaults.object(forKey: "speechWait") as? Double ?? 8
        assistantContextLimit = defaults.object(forKey: "assistantContextLimit") as? Int ?? 16
        systemVoice = defaults.string(forKey: "systemVoice") ?? ""
        ttsVoice = defaults.string(forKey: "ttsVoice") ?? "alloy"
        assistantPrompt = defaults.string(forKey: "assistantPrompt") ?? ""
        assistantChatID = defaults.string(forKey: "assistantChatID").flatMap(UUID.init(uuidString:))
    }

    // MARK: Model connections

    func connection(_ role: ModelRole) -> ModelConnection {
        switch role {
        case .chat: ModelConnection(provider: chatProvider, baseURL: baseURL, model: defaultModel, sameAsDefault: false)
        case .decision: decisionConnection
        case .transcription: transcriptionConnection
        case .speech: speechConnection
        }
    }

    func token(_ role: ModelRole) -> String {
        role == .chat ? token : Keychain.token(role.keychainAccount) ?? ""
    }

    func setConnection(_ connection: ModelConnection, token newToken: String, for role: ModelRole) {
        switch role {
        case .chat:
            chatProvider = connection.provider
            baseURL = connection.baseURL
            token = newToken
            defaultModel = connection.model.trimmingCharacters(in: .whitespaces)
        case .decision: decisionConnection = connection
        case .transcription: transcriptionConnection = connection
        case .speech: speechConnection = connection
        }
        if role != .chat { Keychain.setToken(connection.sameAsDefault ? nil : newToken, role.keychainAccount) }
    }

    /// Where to call the model of a role; nil when it has none (or a bad address).
    func endpoint(_ role: ModelRole) -> ModelEndpoint? {
        ModelConnection.resolve(connection(role), token: token(role), defaultURL: baseURL, defaultToken: token)
    }

    private func save(_ connection: ModelConnection, _ role: ModelRole) {
        defaults.set(try? JSONEncoder().encode(connection), forKey: "connection." + role.rawValue)
    }

    private static func load(_ role: ModelRole) -> ModelConnection? {
        UserDefaults.standard.data(forKey: "connection." + role.rawValue).flatMap { try? JSONDecoder().decode(ModelConnection.self, from: $0) }
    }

    var isConfigured: Bool {
        !token.isEmpty && !defaultModel.isEmpty && normalizedBaseURL != nil
    }

    var normalizedBaseURL: URL? {
        Self.normalize(baseURL)
    }

    nonisolated static func normalize(_ string: String) -> URL? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }
}
