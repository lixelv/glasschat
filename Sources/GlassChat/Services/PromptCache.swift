import Foundation
import os

let chatLog = Logger(subsystem: "dev.lixelv.glasschat", category: "chat")

/// Claude models cache a prompt's prefix only where it is marked (OpenRouter passes the marks on). The prefix is
/// tools → system → messages: a mark on the system prompt keeps the tools and the prompt, one on the last message
/// keeps the history, so the next round of an answer (after app_say) and the next question read them from the cache.
enum PromptCache {
    static func applies(to model: String) -> Bool {
        let id = model.lowercased()
        return id.hasPrefix("anthropic/") || id.contains("claude")
    }

    /// The messages with the system prompt and the last message with text marked; unchanged for other models.
    static func mark(_ messages: [JSONValue], model: String) -> [JSONValue] {
        guard applies(to: model) else { return messages }
        var result = messages
        if let first = result.firstIndex(where: { $0["role"]?.string == "system" }), let marked = Self.marked(result[first]) {
            result[first] = marked
        }
        for i in result.indices.reversed() where result[i]["role"]?.string != "tool" {
            if let marked = Self.marked(result[i]) {
                result[i] = marked
                break
            }
        }
        return result
    }

    /// The message with its text (or its last text part) marked; nil when it has no text.
    private static func marked(_ message: JSONValue) -> JSONValue? {
        guard case .object(var fields) = message else { return nil }
        let mark: JSONValue = .object(["type": .string("ephemeral")])
        switch fields["content"] {
        case .string(let text)? where !text.isEmpty:
            fields["content"] = .array([.object(["type": .string("text"), "text": .string(text), "cache_control": mark])])
        case .array(var parts)?:
            guard let last = parts.lastIndex(where: { $0["type"]?.string == "text" }),
                  case .object(var part) = parts[last] else { return nil }
            part["cache_control"] = mark
            parts[last] = .object(part)
            fields["content"] = .array(parts)
        default:
            return nil
        }
        return .object(fields)
    }
}
