#if DEBUG
import Foundation

extension SelfTests {
    static func tokens() {
        expect(PromptCache.applies(to: "anthropic/claude-haiku-5.5"), "Anthropic through OpenRouter is cached")
        expect(PromptCache.applies(to: "claude-haiku-5-5"), "a Claude model is cached")
        expect(!PromptCache.applies(to: "openai/gpt-5"), "other models are not marked")

        let system = JSONValue.object(["role": .string("system"), "content": .string("You are the assistant.")])
        let user1 = JSONValue.object(["role": .string("user"), "content": .string("Hi")])
        let reply = JSONValue.object(["role": .string("assistant"), "content": .string("Hello")])
        let user2 = JSONValue.object(["role": .string("user"), "content": .string("Weather?")])
        let tool = JSONValue.object(["role": .string("tool"), "tool_call_id": .string("c1"), "content": .string("8°C")])
        let marked = PromptCache.mark([system, user1, reply, user2, tool], model: "anthropic/claude-haiku-5.5")
        func cached(_ message: JSONValue) -> Bool {
            message["content"]?.array?.last?["cache_control"]?["type"]?.string == "ephemeral"
        }
        expect(cached(marked[0]) && marked[0]["content"]?.array?.first?["text"]?.string == "You are the assistant.",
               "the system prompt is a cached part")
        expect(cached(marked[3]), "the last message with text is cached")
        expect(marked[1] == user1 && marked[2] == reply && marked[4] == tool, "the others stay as they were")
        expect(PromptCache.mark([system, user1], model: "openai/gpt-5") == [system, user1], "other models: unchanged")

        let parts = JSONValue.object(["role": .string("user"), "content": .array([
            .object(["type": .string("image_url"), "image_url": .object(["url": .string("data:")])]),
            .object(["type": .string("text"), "text": .string("What is it?")]),
        ])])
        let withParts = PromptCache.mark([system, parts], model: "anthropic/claude-haiku-5.5")
        expect(cached(withParts[1]) && withParts[1]["content"]?.array?.count == 2, "a message of parts: its last text part is cached")
    }
}
#endif
