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
