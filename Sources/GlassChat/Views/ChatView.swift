import SwiftUI

struct ChatView: View {
    let chatID: Chat.ID

    @Environment(ChatController.self) private var controller
    @State private var draft = ""
    @State private var attachments: [Attachment] = []
    @State private var dropping = false
    @State private var composerHeight: CGFloat = 46
    @State private var showPrompt = false
    @State private var viewportHeight: CGFloat = 0
    private static let bottomID = "bottom"
    private var store = ChatStore.shared

    init(chatID: Chat.ID) {
        self.chatID = chatID
    }

    var body: some View {
        let chat = store.chat(chatID)
        let messages = chat?.messages ?? []
        Group {
            if messages.isEmpty {
                // No ScrollView at all for an empty chat: it lit up under the pointer.
                EmptyChat(model: chat.map { $0.model.isEmpty ? AppSettings.shared.defaultModel : $0.model } ?? "")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Messages start at the top; the column is at least as tall as the view,
                        // so the ScrollView never has bare space of its own (it lit up under the pointer).
                        LazyVStack(spacing: 18) {
                            ForEach(messages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }
                            Color.clear.frame(height: 1).id(Self.bottomID)
                        }
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                        .contentShape(.rect)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height - 32 } action: { viewportHeight = max($0, 0) }
                    .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                    .onChange(of: messages.count) { withAnimation(.smooth) { proxy.scrollTo(Self.bottomID, anchor: .bottom) } }
                    .onChange(of: messages.last?.content.count) {
                        if controller.isStreaming(chatID) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let error = controller.errors[chatID] {
                    ErrorBanner(error: error,
                                retry: { controller.retry(chatID) },
                                dismiss: { controller.errors[chatID] = nil })
                }
                if !dropping {
                    HStack {
                        ModelPicker(chatID: chatID)
                        Spacer()
                    }
                    .transition(.opacity)
                }
                Composer(chatID: chatID,
                         text: $draft,
                         attachments: $attachments,
                         isDropTarget: dropping,
                         // Twice as tall, taking in the model picker's row (its 28 pt and the 10 pt gap).
                         dropHeight: composerHeight * 2 + 38,
                         isStreaming: controller.isStreaming(chatID),
                         send: send,
                         stop: { controller.stop(chatID) })
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if !dropping { composerHeight = height }
                    }
            }
            // A little wider than the column of messages.
            .frame(maxWidth: 820)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let imported = urls.filter(\.isFileURL).compactMap { try? AttachmentStore.importFile(at: $0) }
            withAnimation(.snappy) { attachments += imported }
            return !imported.isEmpty
        } isTargeted: { targeted in
            withAnimation(.spring(duration: 0.3)) { dropping = targeted }
        }
        .navigationTitle("")
        .toolbar(removing: .title)
        // The title bar shows the chat's own background: a toolbar backdrop of its own was a lighter band.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarSpacer(.flexible)
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
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        let files = attachments
        draft = ""
        attachments = []
        controller.send(text, attachments: files, in: chatID)
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
