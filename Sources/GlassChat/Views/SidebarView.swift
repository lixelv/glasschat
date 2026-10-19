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
                Section {
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
                } header: {
                    Text(section.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.text)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.sidebar)
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

    /// As in Notes: the title in bold, then the date and the start of the latest message.
    private func row(_ chat: Chat) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(chat.updatedAt, format: .dateTime.day(.twoDigits).month(.twoDigits).year())
                        .foregroundStyle(Palette.text)
                    Text(Self.preview(of: chat))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
                .font(.callout)
            }
            Spacer(minLength: 0)
            if controller.isStreaming(chat.id) {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 5)
        .listRowSeparator(.visible)
        .listRowSeparatorTint(Palette.separator)
    }

    private static func preview(of chat: Chat) -> String {
        let last = chat.messages.last { !$0.content.isEmpty }?.content ?? "No messages"
        return last.split(whereSeparator: \.isNewline).first.map(String.init) ?? last
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
