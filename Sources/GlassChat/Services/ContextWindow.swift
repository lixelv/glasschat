import Foundation

/// The part of a chat that is sent to the model when a chat has a message limit.
enum ContextWindow {
    /// The last `limit` messages, starting at a user message; `limit` 0 or less keeps them all.
    static func slice(_ messages: [Message], limit: Int) -> [Message] {
        guard limit > 0 else { return messages }
        var result = messages.suffix(limit)
        while let first = result.first, first.role != .user { result = result.dropFirst() }
        return Array(result)
    }
}
