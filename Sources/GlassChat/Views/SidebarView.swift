import SwiftUI

struct SidebarView: View {
    @Binding var selection: Chat.ID?
    let newChat: () -> Void

    @Environment(ChatController.self) private var controller
    @State private var search = ""
    @State private var renaming: Chat.ID?
    @State private var newTitle = ""
    private var store = ChatStore.shared

    init(selection: Binding<Chat.ID?>, newChat: @escaping () -> Void) {
        _selection = selection
        self.newChat = newChat
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.chats) { chat in
                        row(chat)
                            .tag(chat.id)
                            .contextMenu {
                                Button("Rename…", systemImage: "pencil") {
                                    newTitle = chat.title
                                    renaming = chat.id
                                }
                                Divider()
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(chat.id) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: "Search")
        .onDeleteCommand { if let selection { delete(selection) } }
        .toolbar {
            ToolbarItem {
                Button("New Chat", systemImage: "square.and.pencil", action: newChat)
                    .help("New Chat (⌘N)")
            }
        }
        .alert("Rename Chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") {
                let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = renaming, !title.isEmpty { store.update(id) { $0.title = title } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func row(_ chat: Chat) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .lineLimit(1)
                Text(chat.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if controller.isStreaming(chat.id) {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
    }

    private func delete(_ id: Chat.ID) {
        if selection == id {
            let rest = store.chats.filter { $0.id != id }
            selection = rest.first?.id
        }
        controller.delete(id)
    }

    private struct ChatSection { let title: String; let chats: [Chat] }

    private var sections: [ChatSection] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let chats = store.chats
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        var groups: [(String, [Chat])] = [("Today", []), ("Yesterday", []), ("Previous 7 Days", []), ("Older", [])]
        for chat in chats {
            let i = calendar.isDateInToday(chat.updatedAt) ? 0
                : calendar.isDateInYesterday(chat.updatedAt) ? 1
                : chat.updatedAt > weekAgo ? 2 : 3
            groups[i].1.append(chat)
        }
        return groups.filter { !$0.1.isEmpty }.map { ChatSection(title: $0.0, chats: $0.1) }
    }
}
