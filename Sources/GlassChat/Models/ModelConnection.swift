import Foundation

/// A server of OpenAI-compatible models; the presets fill in their address.
enum ModelProvider: String, Codable, CaseIterable, Sendable {
    case openAI, openRouter, ollama, lmStudio, custom

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .custom: "Custom"
        }
    }

    var defaultURL: String? {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .ollama: "http://localhost:11434/v1"
        case .lmStudio: "http://localhost:1234/v1"
        case .custom: nil
        }
    }

    /// The provider an address belongs to (settings saved before providers existed).
    static func detect(_ url: String) -> ModelProvider {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespaces)), let host = parsed.host() else { return .custom }
        if host.hasSuffix("openai.com") { return .openAI }
        if host.hasSuffix("openrouter.ai") { return .openRouter }
        if parsed.port == 11434 { return .ollama }
        if parsed.port == 1234 { return .lmStudio }
        return .custom
    }
}

/// What a model is used for; each has its own connection.
enum ModelRole: String, CaseIterable, Sendable {
    case chat, decision

    var title: String {
        switch self {
        case .chat: "Default Model"
        case .decision: "Decision Model"
        }
    }

    /// What is used without a model (nil: a model is needed).
    var noneTitle: String? {
        switch self {
        case .chat: nil
        case .decision: "None (match words)"
        }
    }

    var keychainAccount: String {
        switch self {
        case .chat: Keychain.mainAccount
        case .decision: Keychain.decisionAccount
        }
    }
}

/// Where a model of a role is asked; the token lives in the Keychain.
struct ModelConnection: Codable, Equatable, Sendable {
    var provider: ModelProvider
    var baseURL: String
    /// Empty: no model (the role's fallback).
    var model: String
    /// The address and token of the default model (not for the default model itself).
    var sameAsDefault: Bool

    /// The address, token and model to call; nil without a model or with a bad address.
    static func resolve(_ connection: ModelConnection, token: String, defaultURL: String, defaultToken: String) -> ModelEndpoint? {
        let model = connection.model.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else { return nil }
        let base = connection.sameAsDefault ? defaultURL : connection.baseURL
        guard let url = AppSettings.normalize(base) else { return nil }
        return ModelEndpoint(url: url, token: connection.sameAsDefault ? defaultToken : token, model: model)
    }
}

struct ModelEndpoint: Equatable, Sendable {
    let url: URL
    let token: String
    let model: String
}
