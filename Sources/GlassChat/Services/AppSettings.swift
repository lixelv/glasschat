import Foundation
import Observation

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()
    static let defaultBaseURL = "https://api.openai.com/v1"

    private let defaults = UserDefaults.standard

    var baseURL: String { didSet { defaults.set(baseURL, forKey: "baseURL") } }
    var defaultModel: String { didSet { defaults.set(defaultModel, forKey: "defaultModel") } }
    var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: "systemPrompt") } }
    var token: String { didSet { Keychain.setToken(token) } }

    /// Tool groups switched off (MCP server names, `AppTool.key`): one choice for every chat.
    var disabledTools: Set<String> { didSet { defaults.set(Array(disabledTools), forKey: "disabledTools") } }

    /// The decision model that ranks tools for `search_tools` (e.g. a Jev model); empty = word search.
    var decisionModel: String { didSet { defaults.set(decisionModel, forKey: "decisionModel") } }
    /// How many tools a search hands to the model.
    var decisionTopN: Int { didSet { defaults.set(decisionTopN, forKey: "decisionTopN") } }
    /// Empty: the same base URL and token as the chat.
    var decisionBaseURL: String { didSet { defaults.set(decisionBaseURL, forKey: "decisionBaseURL") } }
    var decisionToken: String { didSet { Keychain.setToken(decisionToken, Keychain.decisionAccount) } }

    // MARK: Notch assistant

    var assistantEnabled: Bool { didSet { defaults.set(assistantEnabled, forKey: "assistantEnabled") } }
    /// The `/audio/transcriptions` model; empty: on-device Apple recognition.
    var transcriptionModel: String { didSet { defaults.set(transcriptionModel, forKey: "transcriptionModel") } }
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
    /// The `/audio/speech` model; empty: the macOS voice.
    var ttsModel: String { didSet { defaults.set(ttsModel, forKey: "ttsModel") } }
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
        decisionModel = defaults.string(forKey: "decisionModel") ?? ""
        decisionTopN = defaults.object(forKey: "decisionTopN") as? Int ?? 4
        decisionBaseURL = defaults.string(forKey: "decisionBaseURL") ?? ""
        decisionToken = Keychain.token(Keychain.decisionAccount) ?? ""
        assistantEnabled = defaults.object(forKey: "assistantEnabled") as? Bool ?? true
        transcriptionModel = defaults.string(forKey: "transcriptionModel") ?? ""
        transcriptionLanguage = defaults.string(forKey: "transcriptionLanguage") ?? ""
        silencePause = defaults.object(forKey: "silencePause") as? Double ?? 1.5
        followUpWindow = defaults.object(forKey: "followUpWindow") as? Double ?? 15
        speechWait = defaults.object(forKey: "speechWait") as? Double ?? 8
        assistantContextLimit = defaults.object(forKey: "assistantContextLimit") as? Int ?? 16
        systemVoice = defaults.string(forKey: "systemVoice") ?? ""
        ttsModel = defaults.string(forKey: "ttsModel") ?? ""
        ttsVoice = defaults.string(forKey: "ttsVoice") ?? "alloy"
        assistantPrompt = defaults.string(forKey: "assistantPrompt") ?? ""
        assistantChatID = defaults.string(forKey: "assistantChatID").flatMap(UUID.init(uuidString:))
    }

    /// Where and with which token the decision model is asked.
    var decisionConnection: (url: URL, token: String)? {
        let trimmed = decisionBaseURL.trimmingCharacters(in: .whitespaces)
        guard let base = trimmed.isEmpty ? normalizedBaseURL : Self.normalize(trimmed) else { return nil }
        return (base, decisionToken.isEmpty ? token : decisionToken)
    }

    var isConfigured: Bool {
        !token.isEmpty && !defaultModel.isEmpty && normalizedBaseURL != nil
    }

    var normalizedBaseURL: URL? {
        Self.normalize(baseURL)
    }

    static func normalize(_ string: String) -> URL? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }
}
