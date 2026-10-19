import AppKit
import UserNotifications

/// The built-in "App" tools: the model talks to the user and works the app — notifications, an alert window,
/// chats, models and MCP servers. Switching chats and models waits until the answer that asked for it is over.
enum AppTool: String, CaseIterable, Sendable {
    case notify = "app_notify"
    case alert = "app_alert"
    case listChats = "app_list_chats"
    case createChat = "app_create_chat"
    case switchChat = "app_switch_chat"
    case renameChat = "app_rename_chat"
    case deleteChat = "app_delete_chat"
    case listModels = "app_list_models"
    case setModel = "app_set_model"
    case listMCP = "app_list_mcp"
    case enableMCP = "app_enable_mcp"
    case disableMCP = "app_disable_mcp"

    /// The key a chat switches these tools off with.
    static let key = "__app__"

    var description: String {
        switch self {
        case .notify: "Show a macOS notification (top right of the screen) with a title and a text."
        case .alert: "Open an alert window the user must close (for something they need to act on). Returns when they close it."
        case .listChats: "List the chats: id, title, model, number of messages; the current one is marked."
        case .createChat: "Create a new empty chat (it does not switch to it). Returns its id."
        case .switchChat: "Show another chat in the window. Takes effect when this answer is finished."
        case .renameChat: "Rename a chat."
        case .deleteChat: "Delete a chat and its messages. The chat of this conversation cannot be deleted."
        case .listModels: "List the model ids the server offers, and the model of this chat."
        case .setModel: "Change the model of a chat (this chat when no chat_id is given). Takes effect when this answer is finished."
        case .listMCP: "List the MCP servers: name, enabled, state, number of tools."
        case .enableMCP: "Enable an MCP server by name (it connects)."
        case .disableMCP: "Disable an MCP server by name (it disconnects)."
        }
    }

    var parameters: JSONValue {
        func string(_ text: String) -> JSONValue { .object(["type": .string("string"), "description": .string(text)]) }
        func object(_ props: [String: JSONValue], _ required: [String]) -> JSONValue {
            .object(["type": .string("object"), "properties": .object(props), "required": .array(required.map(JSONValue.string))])
        }
        let chatID = string("The chat's id from app_list_chats")
        switch self {
        case .notify: return object(["title": string("Title"), "body": string("Text")], ["title"])
        case .alert:
            return object(["title": string("Title"), "message": string("Text, may hold several lines"),
                           "style": .object(["type": .string("string"), "enum": .array(["info", "warning", "critical"].map(JSONValue.string))])],
                          ["title", "message"])
        case .listChats, .listModels, .listMCP: return object([:], [])
        case .createChat: return object(["title": string("Title (optional)"), "model": string("Model id (optional; else the current default)")], [])
        case .switchChat, .deleteChat: return object(["chat_id": chatID], ["chat_id"])
        case .renameChat: return object(["chat_id": chatID, "title": string("New title")], ["chat_id", "title"])
        case .setModel: return object(["model": string("Model id"), "chat_id": chatID], ["model"])
        case .enableMCP, .disableMCP: return object(["name": string("The server's name from app_list_mcp")], ["name"])
        }
    }

    // MARK: Running

    /// Runs the tool for the answer being written in `chatID`; the text goes back to the model.
    @MainActor
    func run(_ args: JSONValue, chatID: Chat.ID, controller: ChatController) async -> (text: String, isError: Bool) {
        do { return (try await perform(args, chatID: chatID, controller: controller), false) }
        catch { return (error.localizedDescription, true) }
    }

    @MainActor
    private func perform(_ args: JSONValue, chatID: Chat.ID, controller: ChatController) async throws -> String {
        let store = ChatStore.shared
        func text(_ key: String) -> String? {
            args[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        func chat() throws -> Chat {
            guard let raw = text("chat_id"), let id = UUID(uuidString: raw), let chat = store.chat(id) else {
                throw MCPError(message: "There is no chat with that id; see app_list_chats.")
            }
            return chat
        }

        switch self {
        case .notify:
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                // macOS asks the user once; do not wait for them for ever.
                let asked = Task { try? await center.requestAuthorization(options: [.alert, .sound]) }
                let answer = await value(of: asked, timeout: 30) ?? nil
                guard answer == true else {
                    throw MCPError(message: "macOS asked the user to allow GlassChat's notifications; they have not allowed them (yet).")
                }
            } else if settings.authorizationStatus == .denied {
                throw MCPError(message: "Notifications are off for GlassChat (System Settings → Notifications). Use app_alert instead.")
            }
            let content = UNMutableNotificationContent()
            content.title = text("title") ?? "GlassChat"
            content.body = text("body") ?? ""
            content.sound = .default
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            return "The notification was shown."

        case .alert:
            let alert = NSAlert()
            alert.messageText = text("title") ?? "GlassChat"
            alert.informativeText = text("message") ?? ""
            alert.alertStyle = switch text("style") { case "critical": .critical; case "info": .informational; default: .warning }
            alert.addButton(withTitle: "OK")
            NSApp.activate()
            // A window of its own; the answer waits for it, the rest of the app keeps running.
            alert.runModal()
            return "The user read the alert and closed it."

        case .listChats:
            let chats: [JSONValue] = store.chats.sorted { $0.updatedAt > $1.updatedAt }.map { chat in
                .object([
                    "id": .string(chat.id.uuidString), "title": .string(chat.title),
                    "model": .string(chat.model.isEmpty ? AppSettings.shared.defaultModel : chat.model),
                    "messages": .number(Double(chat.messages.count)),
                    "current": .bool(chat.id == chatID),
                ])
            }
            return JSONValue.array(chats).prettyString

        case .createChat:
            let created = store.newChat(model: text("model") ?? AppSettings.shared.defaultModel)
            if let title = text("title") { store.update(created.id) { $0.title = title } }
            return "Created the chat \(created.id.uuidString). Use app_switch_chat to show it."

        case .switchChat:
            let target = try chat()
            controller.afterAnswer(in: chatID) {
                NotificationCenter.default.post(name: .selectChat, object: target.id)
            }
            return "The window shows \"\(target.title)\" once this answer is finished."

        case .renameChat:
            let target = try chat()
            guard let title = text("title") else { throw MCPError(message: "A \"title\" is needed.") }
            store.update(target.id) { $0.title = title }
            return "Renamed to \"\(title)\"."

        case .deleteChat:
            let target = try chat()
            guard target.id != chatID else { throw MCPError(message: "This conversation's own chat cannot be deleted.") }
            controller.delete(target.id)
            NotificationCenter.default.post(name: .chatDeleted, object: target.id)
            return "Deleted \"\(target.title)\"."

        case .listModels:
            if ModelStore.shared.models.isEmpty { await ModelStore.shared.refresh() }
            let current = store.chat(chatID)?.model ?? ""
            return JSONValue.object([
                "current": .string(current.isEmpty ? AppSettings.shared.defaultModel : current),
                "models": .array(ModelStore.shared.models.map(JSONValue.string)),
            ]).prettyString

        case .setModel:
            guard let model = text("model") else { throw MCPError(message: "A \"model\" is needed.") }
            let target = text("chat_id") == nil ? store.chat(chatID) : try chat()
            guard let target else { throw MCPError(message: "There is no such chat.") }
            controller.afterAnswer(in: chatID) {
                store.update(target.id) { $0.model = model }
                AppSettings.shared.defaultModel = model
            }
            return "\"\(target.title)\" uses \(model) once this answer is finished."

        case .listMCP:
            let mcp = MCPManager.shared
            let list: [JSONValue] = mcp.servers.map { server in
                let state: String = switch mcp.status[server.id] {
                case .connected?: "connected"
                case .connecting?: "connecting"
                case .failed(let message)?: "failed: \(message)"
                default: server.enabled ? "not connected" : "disabled"
                }
                return .object(["name": .string(server.name), "enabled": .bool(server.enabled), "state": .string(state),
                                "tools": .number(Double(mcp.tools[server.id]?.count ?? 0))])
            }
            return JSONValue.array(list).prettyString

        case .enableMCP, .disableMCP:
            guard let name = text("name") else { throw MCPError(message: "A \"name\" is needed.") }
            try MCPManager.shared.setEnabled(name, self == .enableMCP)
            return "\"\(name)\" is \(self == .enableMCP ? "enabled; it connects and its tools are offered from the next message" : "disabled")."
        }
    }
}

extension Notification.Name {
    /// object: the `Chat.ID` to show.
    static let selectChat = Notification.Name("GlassChat.selectChat")
    /// object: the `Chat.ID` that was deleted.
    static let chatDeleted = Notification.Name("GlassChat.chatDeleted")
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension JSONValue {
    var prettyString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self)
    }
}
