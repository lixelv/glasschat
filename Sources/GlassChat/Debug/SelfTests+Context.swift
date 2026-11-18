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
        // The three places: the compact notch is heard only, so the model opens it to show something.
        let standard = AssistantPrompt.standard
        expect(["compact notch", "expanded notch", "window", "glasschat__app_expand_notch"].allSatisfy(standard.contains),
               "the standard prompt tells the three places and how to open the notch")
        expect(AssistantPrompt.previous.contains { $0.contains("glasschat___app_read_clipboard") && !$0.contains("compact notch") },
               "the prompt before the three places is a former standard")
        expect(AssistantPrompt.note(.notch).contains("glasschat__app_expand_notch") && AssistantPrompt.note(.notch).contains("compact"),
               "in the compact notch the model is told to open it to show something")
        expect(AssistantPrompt.note(.expandedNotch).contains("expanded") && AssistantPrompt.note(.window).contains("window"),
               "the open notch and the window are told apart")
    }
}
#endif
