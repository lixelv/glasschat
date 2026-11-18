import AppKit
import UserNotifications

/// The built-in "App" tools: the model talks to the user and works the app — notifications, an alert window,
/// the clipboard, chats, models and MCP servers. Switching chats and models waits until the answer that asked for it is over.
enum AppTool: String, CaseIterable, Sendable {
    case notify = "_app_notify"
    case alert = "_app_alert"
    case readClipboard = "_app_read_clipboard"
    case writeClipboard = "_app_write_clipboard"
    case listChats = "_app_list_chats"
    case createChat = "_app_create_chat"
    case switchChat = "_app_switch_chat"
    case renameChat = "_app_rename_chat"
    case deleteChat = "_app_delete_chat"
    case listModels = "_app_list_models"
    case setModel = "_app_set_model"
    case listMCP = "_app_list_mcp"
    case enableMCP = "_app_enable_mcp"
    case disableMCP = "_app_disable_mcp"
    case say = "app_say"
    case askUser = "app_ask_user"
    case read = "app_read"
    case write = "app_write"
    case edit = "app_edit"
    case bash = "app_bash"
    case visualize = "app_visualize"
    case installLibrary = "_app_install_library"
    case removeLibrary = "_app_remove_library"

    /// The start of the switch keys of the built-in tools (`AppModule.key`).
    static let key = "__app__"

    var module: AppModule {
        switch self {
        case .say, .askUser: .necessary
        case .read, .write, .edit, .bash: .files
        case .notify, .alert: .user
        case .readClipboard, .writeClipboard: .clipboard
        case .listChats, .createChat, .switchChat, .renameChat, .deleteChat: .chats
        case .listModels, .setModel: .models
        case .listMCP, .enableMCP, .disableMCP: .mcp
        case .visualize, .installLibrary, .removeLibrary: .visualize
        }
    }

    @MainActor
    var description: String {
        switch self {
        case .visualize: VisualDirectives.description(libraries: VisualLibraries.shared.entries)
        case .installLibrary: "Install an npm library for app_visualize from jsDelivr (its js and css entry points, or the given file; at most 10 MB). The user may be asked first. It is offered to visualizations by its name from then on."
        case .removeLibrary: "Remove a library of app_visualize by its name."
        case .notify: "Show a macOS notification (top right of the screen) with a title and a text."
        case .alert: "Open an alert window the user must close (for something they need to act on). Returns when they close it."
        case .readClipboard: "Read the text on the clipboard. Use it only when the user asks to (\"what did I copy\", \"translate what's on the clipboard\"); never look at it on your own."
        case .writeClipboard: "Put a text on the clipboard, replacing what is there. Use it only when the user asks to copy something; never change it on your own."
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
        case .read: "Read a file on this Mac as numbered lines (up to 2000; use offset and limit for more), or list a folder (folders end with /). Paths: absolute, ~/…, or relative to the chat's working folder (see app_bash)."
        case .write: "Create or replace a file with the given content (missing folders are created). Read a file before replacing it."
        case .edit: "Replace an exact piece of text in a file. old_string must occur once, unless replace_all is true; include enough surrounding text to make it unique."
        case .bash: "Run a command in zsh on this Mac (a login shell, so the user's PATH). The working folder starts at the home folder and a cd is remembered for this chat. Returns stdout and stderr (cut at 30000 characters) and the exit code. Timeout 120 s by default, at most 600 s."
        case .askUser: "Ask 1-4 questions with answer options; waits for the user's pick, reply or skip."
        case .say: "Say a text aloud to the user (the macOS voice, or the TTS model from Settings). Returns when it has been spoken."
        }
    }

    var parameters: JSONValue {
        func string(_ text: String) -> JSONValue { .object(["type": .string("string"), "description": .string(text)]) }
        func object(_ props: [String: JSONValue], _ required: [String]) -> JSONValue {
            .object(["type": .string("object"), "properties": .object(props), "required": .array(required.map(JSONValue.string))])
        }
        let chatID = string("The chat's id from _app_list_chats")
        switch self {
        case .notify: return object(["title": string("Title"), "body": string("Text")], ["title"])
        case .alert:
            return object(["title": string("Title"), "message": string("Text, may hold several lines"),
                           "style": .object(["type": .string("string"), "enum": .array(["info", "warning", "critical"].map(JSONValue.string))])],
                          ["title", "message"])
        case .listChats, .listModels, .listMCP, .readClipboard: return object([:], [])
        case .writeClipboard: return object(["text": string("The text to put on the clipboard")], ["text"])
        case .createChat: return object(["title": string("Title (optional)"), "model": string("Model id (optional; else the current default)")], [])
        case .switchChat, .deleteChat: return object(["chat_id": chatID], ["chat_id"])
        case .renameChat: return object(["chat_id": chatID, "title": string("New title")], ["chat_id", "title"])
        case .setModel: return object(["model": string("Model id"), "chat_id": chatID], ["model"])
        case .enableMCP, .disableMCP: return object(["name": string("The server's name from _app_list_mcp")], ["name"])
        case .say: return object(["text": string("What to say, as plain words (no Markdown)")], ["text"])
        case .visualize:
            return object(["html": string("The page body: markup, <style> and <script>"),
                           "libraries": .object(["type": .string("array"), "items": .object(["type": .string("string")]),
                                                 "description": .string("Names of the libraries it uses")]),
                           "height": .object(["type": .string("number"), "description": .string("Minimum pixels; it grows to fit the content")]),
                           "title": string("A few words on what it shows")], ["html"])
        case .installLibrary:
            return object(["package": string("The npm package (\"d3\", \"@observablehq/plot\")"),
                           "version": string("A version or range (default: latest)"),
                           "file": string("A file in the package (default: its entry points)"),
                           "global": string("The global it defines (\"d3\")"),
                           "purpose": string("What it draws, for later")], ["package", "purpose"])
        case .removeLibrary: return object(["name": string("The library's name")], ["name"])
        case .read:
            return object(["path": string("The file or folder"),
                           "offset": .object(["type": .string("integer"), "description": .string("The first line to read, from 1")]),
                           "limit": .object(["type": .string("integer"), "description": .string("How many lines (default 2000)")])], ["path"])
        case .write: return object(["path": string("The file"), "content": string("The whole new content")], ["path", "content"])
        case .bash:
            return object(["command": string("The command"),
                           "timeout": .object(["type": .string("number"), "description": .string("Seconds (default 120, at most 600)")])],
                          ["command"])
        case .edit:
            return object(["path": string("The file"), "old_string": string("The exact text to replace"),
                           "new_string": string("The text to put instead"),
                           "replace_all": .object(["type": .string("boolean"), "description": .string("Replace every occurrence")])],
                          ["path", "old_string", "new_string"])
        case .askUser:
            let text: JSONValue = .object(["type": .string("string")])
            let option = object(["label": text, "description": text], ["label"])
            let question = object([
                "question": text,
                "header": text,
                "options": .object(["type": .string("array"), "items": option, "maxItems": .number(6)]),
                "multi_select": .object(["type": .string("boolean")]),
            ], ["question", "options"])
            return object(["questions": .object(["type": .string("array"), "items": question, "maxItems": .number(4)])], ["questions"])
        }
    }

    // MARK: Running

    /// Runs the tool for the answer being written in `chatID`; the text goes back to the model.
    @MainActor
    func run(_ args: JSONValue, chatID: Chat.ID, callID: String, controller: ChatController) async -> (text: String, isError: Bool) {
        do { return (try await perform(args, chatID: chatID, callID: callID, controller: controller), false) }
        catch { return (error.localizedDescription, true) }
    }

    @MainActor
    private func perform(_ args: JSONValue, chatID: Chat.ID, callID: String, controller: ChatController) async throws -> String {
        let store = ChatStore.shared
        func text(_ key: String) -> String? {
            args[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        func chat() throws -> Chat {
            guard let raw = text("chat_id"), let id = UUID(uuidString: raw), let chat = store.chat(id) else {
                throw MCPError(message: "There is no chat with that id; see _app_list_chats.")
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
                throw MCPError(message: "Notifications are off for GlassChat (System Settings → Notifications). Find and use _app_alert instead.")
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

        case .readClipboard:
            return NSPasteboard.general.string(forType: .string)?.nilIfEmpty ?? "The clipboard has no text."

        case .writeClipboard:
            // Copied as given, spaces and new lines included.
            guard let copied = args["text"]?.string, !copied.isEmpty else { throw MCPError(message: "A \"text\" is needed.") }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copied, forType: .string)
            return "Copied to the clipboard."

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
            return "Created the chat \(created.id.uuidString). Use _app_switch_chat to show it."

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
            if self == .enableMCP,
               let action = RegistryGate.action(for: rawValue, args: args, existing: MCPManager.shared.entry(name)) {
                try await ActionGate.check(action, callID: callID, chat: chatID)
            }
            try MCPManager.shared.setEnabled(name, self == .enableMCP)
            return "\"\(name)\" is \(self == .enableMCP ? "enabled; it connects and its tools are offered from the next message" : "disabled")."

        case .say:
            guard let words = text("text") else { throw MCPError(message: "A \"text\" is needed.") }
            // In the notch the user may hold the shortcut and talk over it: the voice goes through the echo canceller.
            let interruptible = chatID == AppSettings.shared.assistantChatID
            return try await Speaker.shared.speak(words, interruptible: interruptible) ? "Spoken." : "Stopped by the user."

        case .visualize:
            guard let html = args["html"]?.string, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MCPError(message: "An \"html\" body is needed.")
            }
            let names = args["libraries"]?.array?.compactMap(\.string) ?? []
            let libraries = VisualLibraries.shared
            let unknown = names.filter { libraries.entry($0) == nil }
            guard unknown.isEmpty else {
                throw MCPError(message: "Unknown libraries: \(unknown.joined(separator: ", ")). Installed: \(libraries.entries.map(\.name).joined(separator: ", ")).")
            }
            let errors = await VisualSandbox.check(html: html, libraries: names.compactMap(libraries.entry))
            // A page that never finished (or could not be shown) is not drawn: an error, so the model fixes it.
            if let stuck = errors.first(where: { $0.hasPrefix("The page did not finish") || $0.hasPrefix("The page could not be shown") }) {
                throw MCPError(message: stuck + " Call app_visualize again with a fix.")
            }
            guard !errors.isEmpty else { return "Shown." }
            return "Shown, but the page reported errors:\n" + errors.prefix(10).joined(separator: "\n")
                + "\nCall app_visualize again with a fix."

        case .installLibrary:
            guard let package = text("package") else { throw MCPError(message: "A \"package\" is needed.") }
            let version = text("version")
            try VisualLibraries.validate(package: package, version: version, file: text("file"))
            if version == nil, text("file") == nil, let bundled = try VisualLibraries.shared.restoreBundled(package) {
                return "\(bundled.name) is available again (bundled, version \(bundled.version))."
            }
            try await ActionGate.check(PendingAction(tool: rawValue, summary: "Download \(package) from jsDelivr",
                                                     detail: "npm package \(package)@\(version ?? "latest") for visualizations (runs only inside the page, without network)",
                                                     dangerous: false),
                                       callID: callID, chat: chatID)
            let entry = try await VisualLibraries.shared.install(package: package, version: version, file: text("file"),
                                                                 global: text("global"), purpose: text("purpose") ?? package)
            return "Installed \(entry.name) \(entry.version) (\(entry.files.joined(separator: ", "))). Use it in app_visualize as \"\(entry.name)\"."

        case .removeLibrary:
            guard let name = text("name") else { throw MCPError(message: "A \"name\" is needed.") }
            try VisualLibraries.shared.remove(name)
            return "Removed \(name)."

        case .read, .write, .edit:
            guard let raw = args["path"]?.string, !raw.isEmpty else { throw MCPError(message: "A \"path\" is needed.") }
            let url = FileTools.resolvePath(raw, cwd: await ShellRunner.shared.workingDirectory(for: chatID))
            if self == .write {
                try await ActionGate.check(PendingAction(tool: rawValue, summary: "Write \(url.path)",
                                                         detail: args["content"]?.string ?? "", dangerous: false),
                                           callID: callID, chat: chatID)
            } else if self == .edit {
                let detail = "- \(args["old_string"]?.string ?? "")\n+ \(args["new_string"]?.string ?? "")"
                try await ActionGate.check(PendingAction(tool: rawValue, summary: "Edit \(url.path)", detail: detail, dangerous: false),
                                           callID: callID, chat: chatID)
            }
            switch self {
            case .read:
                let offset = args["offset"]?.int, limit = args["limit"]?.int
                return try await Task.detached { try FileTools.read(url, offset: offset, limit: limit) }.value
            case .write:
                guard let content = args["content"]?.string else { throw MCPError(message: "A \"content\" is needed.") }
                return try await Task.detached { try FileTools.write(url, content: content) }.value
            default:
                guard let old = args["old_string"]?.string, let new = args["new_string"]?.string else {
                    throw MCPError(message: "\"old_string\" and \"new_string\" are needed.")
                }
                let all: Bool = { if case .bool(true)? = args["replace_all"] { return true }; return false }()
                return try await Task.detached { try FileTools.edit(url, old: old, new: new, replaceAll: all) }.value
            }

        case .bash:
            guard let command = text("command") else { throw MCPError(message: "A \"command\" is needed.") }
            let timeout = min(max(args["timeout"]?.double ?? ShellRunner.defaultTimeout, 1), ShellRunner.maxTimeout)
            let folder = await ShellRunner.shared.workingDirectory(for: chatID).path
            try await ActionGate.check(PendingAction(tool: rawValue, summary: "Run a command in \(folder)", detail: command, dangerous: false),
                                       callID: callID, chat: chatID)
            let result = await ShellRunner.shared.run(command, in: chatID, timeout: timeout)
            var reply = result.output.isEmpty ? "(no output)" : result.output
            if result.timedOut { reply += "\nTimed out after \(Int(timeout)) s." }
            return reply + "\nExit code: \(result.exitCode)"

        case .askUser:
            let questions = try AskUser.parse(args)
            guard let answers = try await QuestionCenter.shared.ask(questions, callID: callID, in: chatID) else {
                throw MCPError(message: "The user dismissed the questions.")
            }
            return AskUser.result(questions, answers)
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
