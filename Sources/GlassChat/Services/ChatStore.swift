import Foundation
import Observation

/// All chats, kept in memory and saved as one JSON file in Application Support.
@Observable
@MainActor
final class ChatStore {
    static let shared = ChatStore()

    private(set) var chats: [Chat] = []
    private var saveTask: Task<Void, Never>?

    private static var fileURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "GlassChat", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "chats.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([Chat].self, from: data) {
            chats = decoded.map { chat in
                var chat = chat
                for i in chat.messages.indices { chat.messages[i].isPartial = false }
                return chat
            }
        }
    }

    func chat(_ id: Chat.ID?) -> Chat? {
        chats.first { $0.id == id }
    }

    @discardableResult
    func newChat(model: String) -> Chat {
        let chat = Chat(model: model)
        chats.insert(chat, at: 0)
        scheduleSave()
        return chat
    }

    /// Changes a chat in place; does nothing when it was deleted meanwhile.
    func update(_ id: Chat.ID, save: Bool = true, _ change: (inout Chat) -> Void) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        change(&chats[i])
        if save { scheduleSave() }
    }

    func delete(_ id: Chat.ID) {
        chats.removeAll { $0.id == id }
        scheduleSave()
    }

    func scheduleSave() {
        saveTask?.cancel()
        let snapshot = chats
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            Self.write(snapshot)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        Self.write(chats)
    }

    private static func write(_ chats: [Chat]) {
        guard let data = try? JSONEncoder().encode(chats) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
