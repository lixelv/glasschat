import Foundation

enum Role: String, Codable, Sendable {
    case user, assistant
}

struct Message: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var role: Role
    var content: String
    var createdAt = Date.now
    var isPartial = false
}

struct Chat: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title = "New Chat"
    var model: String
    var systemPrompt: String?
    var createdAt = Date.now
    var updatedAt = Date.now
    var messages: [Message] = []
}
