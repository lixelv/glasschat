import Foundation
import Observation

/// Sends messages and streams answers. State is keyed by chat id, so a stream
/// keeps writing into its own chat whatever is selected.
@Observable
@MainActor
final class ChatController {
    private(set) var streaming: Set<Chat.ID> = []
    var errors: [Chat.ID: APIError] = [:]
    private var tasks: [Chat.ID: Task<Void, Never>] = [:]
    /// What the app tools asked to do once the answer of a chat is over (switch chat, change model).
    private var pending: [Chat.ID: [() -> Void]] = [:]
    /// Missing commands the model was already asked to tell the user about, per chat.
    private var toldMissing: Set<String> = []

    func afterAnswer(in id: Chat.ID, _ action: @escaping () -> Void) {
        pending[id, default: []].append(action)
    }

    private let store = ChatStore.shared
    private let settings = AppSettings.shared

    func isStreaming(_ id: Chat.ID) -> Bool { streaming.contains(id) }

    /// The most rounds of tool calls in one answer.
    static let maxToolRounds = 20

    func send(_ text: String, attachments: [Attachment] = [], in id: Chat.ID) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty, !isStreaming(id), let chat = store.chat(id) else { return }
        guard let baseURL = settings.normalizedBaseURL else {
            errors[id] = APIError(status: nil, message: "The base URL is not valid. Open Settings to fix it.", url: nil)
            return
        }
        errors[id] = nil

        let assistant = Message(role: .assistant, content: "", isPartial: true)
        store.update(id) { chat in
            if chat.title == "New Chat" {
                chat.title = Self.title(from: text.isEmpty ? attachments.map(\.name).joined(separator: ", ") : text)
            }
            chat.messages.append(Message(role: .user, content: text, attachments: attachments))
            chat.messages.append(assistant)
            chat.updatedAt = .now
        }

        let prompt = (chat.systemPrompt ?? settings.systemPrompt).trimmingCharacters(in: .whitespacesAndNewlines)
        var turns: [JSONValue] = prompt.isEmpty ? [] : [.object(["role": .string("system"), "content": .string(prompt)])]
        if let note = missingCommandNote(chat) {
            turns.append(.object(["role": .string("system"), "content": .string(note)]))
        }
        for message in store.chat(id)!.messages where message.id != assistant.id {
            turns += Self.turns(of: message)
        }

        let client = OpenAIClient(baseURL: baseURL, token: settings.token)
        let model = chat.model.isEmpty ? settings.defaultModel : chat.model
        streaming.insert(id)
        let found = FoundTools()
        tasks[id] = Task {
            do {
                for _ in 0..<Self.maxToolRounds {
                    // Read every round: the registry tools may have changed the servers.
                    let functions = MCPManager.shared.functions(disabled: AppSettings.shared.disabledTools, found: found.names)
                    let tools = functions.keys.sorted().compactMap { functions[$0]?.definition }
                    var calls: [Int: ToolCall] = [:]
                    for try await event in client.streamChat(model: model, messages: turns, tools: tools) {
                        switch event {
                        case .text(let delta):
                            edit(id, assistant.id) { $0.content += delta }
                        case .toolCall(let index, let callID, let name, let arguments):
                            var call = calls[index] ?? ToolCall(id: callID ?? "call_\(index)", name: "", arguments: "")
                            if let callID, !callID.isEmpty { call.id = callID }
                            if let name { call.name += name }
                            call.arguments += arguments
                            calls[index] = call
                        case .usage(let input, let output):
                            // Each round of tool calls is a request of its own: they add up.
                            edit(id, assistant.id) {
                                $0.inputTokens = ($0.inputTokens ?? 0) + input
                                $0.outputTokens = ($0.outputTokens ?? 0) + output
                            }
                        case .finish:
                            break
                        }
                    }
                    let started = Date.now
                    let round = calls.keys.sorted().compactMap { calls[$0] }.filter { !$0.name.isEmpty }
                        .map { call -> ToolCall in var call = call; call.startedAt = started; return call }
                    if round.isEmpty { break }
                    try Task.checkCancellation()

                    // The text so far belongs to this step; the next round writes a new one.
                    let stepText = store.chat(id)?.messages.first { $0.id == assistant.id }?.content ?? ""
                    let step = ToolStep(text: stepText, calls: round)
                    edit(id, assistant.id) { $0.steps.append(step); $0.content = "" }
                    turns.append(.object([
                        "role": .string("assistant"),
                        "content": stepText.isEmpty ? .null : .string(stepText),
                        "tool_calls": .array(round.map(Self.toolCallJSON)),
                    ]))

                    // Calls of one round run together; each result shows as soon as it is there.
                    let running = round.map { call in
                        Task { () -> (String, Bool) in
                            guard let function = functions[call.name] else { return ("Unknown tool \(call.name).", true) }
                            let (text, isError): (String, Bool)
                            if case .search = function.target {
                                (text, isError) = await Self.searchTools(call.arguments, found: found)
                            } else if case .app(let tool) = function.target {
                                let args = call.arguments.trimmingCharacters(in: .whitespaces).isEmpty ? .object([:]) : JSONValue.parse(call.arguments)
                                (text, isError) = args == nil ? ("The arguments are not valid JSON.", true)
                                    : await tool.run(args!, chatID: id, controller: self)
                            } else {
                                (text, isError) = await MCPManager.shared.call(function, arguments: call.arguments)
                            }
                            self.edit(id, assistant.id) { message in
                                guard let s = message.steps.firstIndex(where: { $0.id == step.id }),
                                      let c = message.steps[s].calls.firstIndex(where: { $0.id == call.id }) else { return }
                                message.steps[s].calls[c].result = text
                                message.steps[s].calls[c].isError = isError
                                message.steps[s].calls[c].finishedAt = .now
                            }
                            return (text, isError)
                        }
                    }
                    var results: [String: (String, Bool)] = [:]
                    // Stop ends the answer at once, even when a tool does not listen to cancellation.
                    for (call, task) in zip(round, running) {
                        guard let value = await value(of: task) else { break }
                        results[call.id] = value
                    }
                    for call in round {
                        turns.append(.object([
                            "role": .string("tool"),
                            "tool_call_id": .string(call.id),
                            "content": .string(results[call.id]?.0 ?? "No result."),
                        ]))
                    }
                    try Task.checkCancellation()
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch let error as APIError {
                errors[id] = error
            } catch {
                errors[id] = APIError(status: nil, message: error.localizedDescription, url: nil)
            }
            finish(id, assistant: assistant.id)
        }
    }

    /// Runs `search_tools`: ranks every tool but the search, and offers the best ones for the rest of the answer.
    private static func searchTools(_ arguments: String, found: FoundTools) async -> (String, Bool) {
        guard let query = JSONValue.parse(arguments)?["query"]?.string, !query.isEmpty else {
            return ("A \"query\" is needed.", true)
        }
        let all = MCPManager.shared.allFunctions()
        let candidates = all.filter { $0.value.group != nil }.mapValues(\.summary)
        do {
            let hits = try await ToolSearch.search(query, among: candidates)
            guard !hits.isEmpty else { return ("No tool fits \"\(query)\".", false) }
            let active = MCPManager.shared.functions(disabled: AppSettings.shared.disabledTools, found: found.names)
            var lines: [String] = []
            for hit in hits {
                let state = active[hit.name] == nil ? "now available" : "already available"
                found.names.insert(hit.name)
                let p = hit.probability.map { String(format: " (%.0f%%)", $0 * 100) } ?? ""
                lines.append("- \(hit.name)\(p), \(state): \(candidates[hit.name] ?? "")")
            }
            return ("Found tools (call them by these names):\n" + lines.joined(separator: "\n"), false)
        } catch {
            return ("The search failed: \(error.localizedDescription)", true)
        }
    }

    /// When an MCP server could not start for want of npx (or another command), the model is asked
    /// (once per chat) to tell the user with an alert how to install it.
    private func missingCommandNote(_ chat: Chat) -> String? {
        guard !AppSettings.shared.disabledTools.contains(AppTool.key) else { return nil }
        let missing = MCPManager.shared.missingCommands.filter { !toldMissing.contains("\(chat.id)|\($0.server)") }
        guard !missing.isEmpty else { return nil }
        for item in missing { toldMissing.insert("\(chat.id)|\(item.server)") }
        let list = missing.map { "\"\($0.server)\" (command `\($0.command)`)" }.joined(separator: ", ")
        let node = missing.contains { ["npx", "npm", "node"].contains($0.command) }
        let how = node
            ? "npx comes with Node.js. Steps: install Homebrew if needed (`/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"`), then `brew install node`, or take the installer from https://nodejs.org; check with `node -v` and `npx -v`; then reconnect the server (Settings → MCP) or restart GlassChat."
            : "Tell them which program is missing and the usual way to install it on macOS (for `uvx`: `brew install uv` or `curl -LsSf https://astral.sh/uv/install.sh | sh`), then to reconnect the server."
        return "Some MCP servers could not start because a command is not installed: \(list). Before you answer, call glasschat__app_alert to tell the user, in their language, to install it, with brief steps. \(how)"
    }

    private func edit(_ id: Chat.ID, _ messageID: Message.ID, _ change: (inout Message) -> Void) {
        store.update(id, save: false) { chat in
            if let i = chat.messages.lastIndex(where: { $0.id == messageID }) { change(&chat.messages[i]) }
        }
    }

    /// A stored message as Chat Completions messages (an answer with tools is several).
    private static func turns(of message: Message) -> [JSONValue] {
        switch message.role {
        case .user:
            guard !message.attachments.isEmpty else {
                return [.object(["role": .string("user"), "content": .string(message.content)])]
            }
            var parts: [JSONValue] = message.content.isEmpty ? [] : [.object(["type": .string("text"), "text": .string(message.content)])]
            parts += message.attachments.compactMap(AttachmentStore.contentPart)
            return [.object(["role": .string("user"), "content": .array(parts)])]
        case .assistant:
            var result: [JSONValue] = []
            for step in message.steps {
                result.append(.object([
                    "role": .string("assistant"),
                    "content": step.text.isEmpty ? .null : .string(step.text),
                    "tool_calls": .array(step.calls.map(toolCallJSON)),
                ]))
                for call in step.calls {
                    result.append(.object([
                        "role": .string("tool"), "tool_call_id": .string(call.id),
                        "content": .string(call.result ?? "No result."),
                    ]))
                }
            }
            if !message.content.isEmpty {
                result.append(.object(["role": .string("assistant"), "content": .string(message.content)]))
            }
            return result
        }
    }

    private static func toolCallJSON(_ call: ToolCall) -> JSONValue {
        .object([
            "id": .string(call.id), "type": .string("function"),
            "function": .object(["name": .string(call.name), "arguments": .string(call.arguments.isEmpty ? "{}" : call.arguments)]),
        ])
    }

    func stop(_ id: Chat.ID) {
        tasks[id]?.cancel()
    }

    /// Sends the last question of the chat again.
    func retry(_ id: Chat.ID) {
        guard !isStreaming(id), let chat = store.chat(id),
              let last = chat.messages.last(where: { $0.role == .user }) else { return }
        store.update(id) { chat in
            if let i = chat.messages.lastIndex(where: { $0.id == last.id }) {
                chat.messages.removeSubrange(i...)
            }
        }
        send(last.content, attachments: last.attachments, in: id)
    }

    func delete(_ id: Chat.ID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        streaming.remove(id)
        errors[id] = nil
        store.delete(id)
    }

    private func finish(_ id: Chat.ID, assistant: Message.ID) {
        streaming.remove(id)
        tasks[id] = nil
        defer {
            for action in pending.removeValue(forKey: id) ?? [] { action() }
        }
        store.update(id) { chat in
            guard let i = chat.messages.lastIndex(where: { $0.id == assistant }) else { return }
            if chat.messages[i].content.isEmpty && chat.messages[i].steps.isEmpty {
                chat.messages.remove(at: i)
            } else {
                chat.messages[i].isPartial = false
                // A call that never answered (stopped) says so.
                for s in chat.messages[i].steps.indices {
                    for c in chat.messages[i].steps[s].calls.indices where chat.messages[i].steps[s].calls[c].result == nil {
                        chat.messages[i].steps[s].calls[c].result = "Stopped."
                        chat.messages[i].steps[s].calls[c].finishedAt = .now
                        chat.messages[i].steps[s].calls[c].isError = true
                    }
                }
            }
            chat.updatedAt = .now
        }
    }

    private static func title(from text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
        return words.count > 60 ? String(words.prefix(60)) + "…" : words
    }
}


/// The tools `search_tools` found during one answer: offered to the model from its next step on.
@MainActor
final class FoundTools {
    var names: Set<String> = []
}
