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
        for message in store.chat(id)!.messages where message.id != assistant.id {
            turns += Self.turns(of: message)
        }

        let client = OpenAIClient(baseURL: baseURL, token: settings.token)
        let model = chat.model.isEmpty ? settings.defaultModel : chat.model
        streaming.insert(id)
        tasks[id] = Task {
            do {
                for _ in 0..<Self.maxToolRounds {
                    // Read every round: the registry tools may have changed the servers.
                    let disabled = store.chat(id)?.disabledServers ?? chat.disabledServers
                    let functions = MCPManager.shared.functions(disabled: disabled)
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
                            let (text, isError) = await MCPManager.shared.call(function, arguments: call.arguments)
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
                    await withTaskCancellationHandler {
                        for (call, task) in zip(round, running) { results[call.id] = await task.value }
                    } onCancel: {
                        for task in running { task.cancel() }
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
