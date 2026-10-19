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

    func send(_ text: String, in id: Chat.ID) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming(id), let chat = store.chat(id) else { return }
        guard let baseURL = settings.normalizedBaseURL else {
            errors[id] = APIError(status: nil, message: "The base URL is not valid. Open Settings to fix it.", url: nil)
            return
        }
        errors[id] = nil

        let assistant = Message(role: .assistant, content: "", isPartial: true)
        store.update(id) { chat in
            if chat.title == "New Chat" { chat.title = Self.title(from: text) }
            chat.messages.append(Message(role: .user, content: text))
            chat.messages.append(assistant)
            chat.updatedAt = .now
        }

        var turns: [ChatTurn] = []
        let prompt = (chat.systemPrompt ?? settings.systemPrompt).trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty { turns.append(ChatTurn(role: "system", content: prompt)) }
        turns += store.chat(id)!.messages
            .filter { $0.id != assistant.id && !$0.content.isEmpty }
            .map { ChatTurn(role: $0.role.rawValue, content: $0.content) }

        let client = OpenAIClient(baseURL: baseURL, token: settings.token)
        let model = chat.model.isEmpty ? settings.defaultModel : chat.model
        streaming.insert(id)
        tasks[id] = Task {
            do {
                for try await delta in client.streamChat(model: model, messages: turns) {
                    store.update(id, save: false) { chat in
                        if let i = chat.messages.lastIndex(where: { $0.id == assistant.id }) {
                            chat.messages[i].content += delta
                        }
                    }
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
        send(last.content, in: id)
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
            if chat.messages[i].content.isEmpty {
                chat.messages.remove(at: i)
            } else {
                chat.messages[i].isPartial = false
            }
            chat.updatedAt = .now
        }
    }

    private static func title(from text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
        return words.count > 60 ? String(words.prefix(60)) + "…" : words
    }
}
