#if DEBUG
import Foundation

extension SelfTests {
    static func models() {
        expect(ModelProvider.detect("https://api.openai.com/v1") == .openAI, "openai detected")
        expect(ModelProvider.detect("https://openrouter.ai/api/v1/") == .openRouter, "openrouter detected")
        expect(ModelProvider.detect("http://localhost:11434/v1") == .ollama, "ollama detected")
        expect(ModelProvider.detect("http://127.0.0.1:1234/v1") == .lmStudio, "lm studio detected")
        expect(ModelProvider.detect("https://example.com/v1") == .custom, "custom")
        expect(ModelProvider.openRouter.defaultURL == "https://openrouter.ai/api/v1", "preset url")
        expect(ModelProvider.custom.defaultURL == nil, "custom has no url")

        let chatURL = "https://api.openai.com/v1"
        let same = ModelConnection(provider: .openAI, baseURL: "", model: "whisper-1", sameAsDefault: true)
        let r1 = ModelConnection.resolve(same, token: "", defaultURL: chatURL, defaultToken: "sk-main")
        expect(r1?.url.absoluteString == chatURL && r1?.token == "sk-main" && r1?.model == "whisper-1", "same as default")
        let own = ModelConnection(provider: .custom, baseURL: "https://x.dev/v1/", model: " m ", sameAsDefault: false)
        let r2 = ModelConnection.resolve(own, token: "t", defaultURL: chatURL, defaultToken: "sk-main")
        expect(r2?.url.absoluteString == "https://x.dev/v1" && r2?.token == "t" && r2?.model == "m", "own connection")
        let none = ModelConnection(provider: .openAI, baseURL: "", model: "", sameAsDefault: true)
        expect(ModelConnection.resolve(none, token: "", defaultURL: chatURL, defaultToken: "k") == nil, "no model = none")
        let bad = ModelConnection(provider: .custom, baseURL: "not a url", model: "m", sameAsDefault: false)
        expect(ModelConnection.resolve(bad, token: "", defaultURL: chatURL, defaultToken: "k") == nil, "bad url = none")
    }
}
#endif
