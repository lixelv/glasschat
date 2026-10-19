import SwiftUI

struct ChatView: View {
    let chatID: Chat.ID

    @Environment(ChatController.self) private var controller
    @State private var draft = ""
    @State private var showPrompt = false
    private var store = ChatStore.shared

    init(chatID: Chat.ID) {
        self.chatID = chatID
    }

    var body: some View {
        let chat = store.chat(chatID)
        let messages = chat?.messages ?? []
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(messages) { message in
                    MessageRow(message: message)
                        .id(message.id)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollContentBackground(.hidden)
        .overlay {
            if messages.isEmpty { EmptyChat(model: chat.map { $0.model.isEmpty ? AppSettings.shared.defaultModel : $0.model } ?? "") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let error = controller.errors[chatID] {
                    ErrorBanner(error: error,
                                retry: { controller.retry(chatID) },
                                dismiss: { controller.errors[chatID] = nil })
                }
                HStack {
                    ModelPicker(chatID: chatID)
                    Spacer()
                }
                Composer(text: $draft,
                         isStreaming: controller.isStreaming(chatID),
                         send: send,
                         stop: { controller.stop(chatID) })
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .navigationTitle(chat?.title ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("System Prompt", systemImage: "text.bubble") { showPrompt.toggle() }
                    .help("System prompt of this chat")
                    .popover(isPresented: $showPrompt, arrowEdge: .bottom) {
                        ChatPromptEditor(chatID: chatID)
                    }
            }
        }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        controller.send(text, in: chatID)
    }
}

private struct EmptyChat: View {
    let model: String

    private static let symbols = [
        "sparkles", "wand.and.stars", "lightbulb.max", "brain.head.profile", "atom",
        "bubble.left.and.text.bubble.right", "text.bubble", "globe.europe.africa",
        "books.vertical", "paintpalette", "leaf", "moon.stars", "graduationcap", "puzzlepiece.extension",
    ]
    /// Picked once per opened chat.
    @State private var symbol = symbols.randomElement()!

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("What can I help with?")
                .font(.title2.weight(.semibold))
            if !model.isEmpty {
                Text(model)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 80)
    }
}

struct ChatPromptEditor: View {
    let chatID: Chat.ID
    private var store = ChatStore.shared

    init(chatID: Chat.ID) { self.chatID = chatID }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System Prompt")
                .font(.headline)
            TextEditor(text: Binding(
                get: { store.chat(chatID)?.systemPrompt ?? "" },
                set: { value in store.update(chatID) { $0.systemPrompt = value.isEmpty ? nil : value } }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            .frame(width: 360, height: 160)
            Text("Empty uses the prompt from Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}
