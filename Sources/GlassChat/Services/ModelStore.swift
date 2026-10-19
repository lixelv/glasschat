import Foundation
import Observation

/// The model ids the server offers (`GET /models`).
@Observable
@MainActor
final class ModelStore {
    static let shared = ModelStore()

    private(set) var models: [String] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    func refresh() async {
        let settings = AppSettings.shared
        guard let url = settings.normalizedBaseURL, !settings.token.isEmpty else { return }
        await load(baseURL: url, token: settings.token)
    }

    /// Loads the models of the given connection; returns whether it worked.
    @discardableResult
    func load(baseURL: URL, token: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            models = try await OpenAIClient(baseURL: baseURL, token: token).listModels()
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
