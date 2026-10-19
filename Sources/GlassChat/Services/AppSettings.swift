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

    private init() {
        baseURL = defaults.string(forKey: "baseURL") ?? Self.defaultBaseURL
        defaultModel = defaults.string(forKey: "defaultModel") ?? ""
        systemPrompt = defaults.string(forKey: "systemPrompt") ?? ""
        token = Keychain.token() ?? ""
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
