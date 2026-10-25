#if DEBUG
import Foundation

extension SelfTests {
    static func context() {
        func msgs(_ roles: String) -> [Message] {
            roles.map { Message(role: $0 == "u" ? .user : .assistant, content: String($0)) }
        }
        let twenty = msgs(String(repeating: "uaua", count: 5))
        expect(ContextWindow.slice(twenty, limit: 0).count == 20, "limit 0 keeps all")
        expect(ContextWindow.slice(twenty, limit: 16).count == 16, "limit 16 of 20")
        expect(ContextWindow.slice(twenty, limit: 16).first?.role == .user, "starts with user")
        expect(ContextWindow.slice(msgs("uaua"), limit: 3).map(\.role) == [.user, .assistant], "assistant at cut is dropped")
        expect(ContextWindow.slice(msgs("uau"), limit: 1).map(\.role) == [.user], "limit 1 keeps the question")
        expect(ContextWindow.slice(msgs("uau"), limit: 5).count == 3, "shorter than limit")
        expect(AssistantPrompt.effective("  ") == AssistantPrompt.standard, "blank prompt = standard")
        expect(AssistantPrompt.effective("Be brief") == "Be brief", "custom prompt kept")
        expect(AssistantPrompt.standard.contains("glasschat__app_say") && AssistantPrompt.standard.contains("every"), "speaks on every request")
        expect(AssistantPrompt.standard.contains("glasschat__search_tools"), "finds the hidden tools")
        expect(AssistantPrompt.stored(nil) == AssistantPrompt.standard && AssistantPrompt.stored("") == AssistantPrompt.standard,
               "an empty saved prompt becomes the real text")
        expect(AssistantPrompt.stored("Mine") == "Mine", "a written prompt is kept")
        expect(AssistantPrompt.previous.allSatisfy { AssistantPrompt.stored($0) == AssistantPrompt.standard },
               "a former standard prompt becomes the current one")
        expect(!AssistantPrompt.standard.contains("shortest"), "the standard prompt does not ask for the shortest answer")
    }
}
#endif
