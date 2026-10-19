import SwiftUI

struct RootView: View {
    @State private var controller = ChatController()
    @State private var selection: Chat.ID?
    @State private var showOnboarding = false
    private var store = ChatStore.shared
    private var settings = AppSettings.shared

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, newChat: newChat)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let id = selection, store.chat(id) != nil {
                ChatView(chatID: id)
                    .id(id)
            } else {
                ContentUnavailableView("No Chat Selected", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Start a new chat with ⌘N."))
            }
        }
        .environment(controller)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .onAppear {
            showOnboarding = !settings.isConfigured
            if selection == nil {
                selection = store.chats.first?.id ?? store.newChat(model: settings.defaultModel).id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in newChat() }
    }

    private func newChat() {
        // Reuse an untouched chat instead of piling up empty ones.
        if let empty = store.chats.first(where: { $0.messages.isEmpty }) {
            store.update(empty.id) { $0.model = settings.defaultModel; $0.updatedAt = .now }
            selection = empty.id
        } else {
            selection = store.newChat(model: settings.defaultModel).id
        }
    }
}
