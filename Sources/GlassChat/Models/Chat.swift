import Foundation

enum Role: String, Codable, Sendable {
    case user, assistant
}

/// A file attached to a user message. The bytes live in Application Support (`AttachmentStore`),
/// only this reference is kept in chats.json.
struct Attachment: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case image, audio, pdf, text, file
    }

    var id = UUID()
    var name: String
    var mimeType: String
    var kind: Kind
    var size: Int
    /// File name inside the attachments folder.
    var storedName: String
}

/// One call of an MCP tool made while the assistant answered.
struct ToolCall: Identifiable, Codable, Hashable, Sendable {
    var id: String
    /// The function name the model used (`server__tool`).
    var name: String
    var arguments: String
    var result: String?
    var isError = false

    var server: String { name.components(separatedBy: "__").first ?? name }
    var tool: String { name.components(separatedBy: "__").dropFirst().joined(separator: "__") }
}

/// A step of an answer: the text the model wrote before it called tools, and those calls.
struct ToolStep: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var calls: [ToolCall]
}

struct Message: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var role: Role
    var content: String
    var createdAt = Date.now
    var isPartial = false
    var attachments: [Attachment] = []
    /// Assistant only: the rounds of tool calls before the final `content`.
    var steps: [ToolStep] = []
    /// Assistant only: tokens read and written over all the requests of the answer, when the server said.
    var inputTokens: Int?
    var outputTokens: Int?

    init(role: Role, content: String, isPartial: Bool = false, attachments: [Attachment] = []) {
        self.role = role
        self.content = content
        self.isPartial = isPartial
        self.attachments = attachments
    }

    // Fields added later are optional in the file, so older chats.json files still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        isPartial = try c.decodeIfPresent(Bool.self, forKey: .isPartial) ?? false
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        steps = try c.decodeIfPresent([ToolStep].self, forKey: .steps) ?? []
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens)
    }
}

struct Chat: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title = "New Chat"
    var model: String
    var systemPrompt: String?
    var createdAt = Date.now
    var updatedAt = Date.now
    var messages: [Message] = []
    /// MCP servers (by name, and `MCPManager.registryKey`) switched off in this chat.
    var disabledServers: Set<String> = []

    init(model: String) {
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "New Chat"
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        messages = try c.decodeIfPresent([Message].self, forKey: .messages) ?? []
        disabledServers = try c.decodeIfPresent(Set<String>.self, forKey: .disabledServers) ?? []
    }
}
