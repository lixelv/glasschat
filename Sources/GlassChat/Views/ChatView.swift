import SwiftUI

struct ChatView: View {
    let chatID: Chat.ID

    @Environment(ChatController.self) private var controller
    @State private var draft = ""
    @State private var attachments: [Attachment] = []
    @Environment(DropZone.self) private var dropZone
    @State private var composerHeight: CGFloat = 46
    @State private var showPrompt = false
    @State private var viewportHeight: CGFloat = 0
    /// Whether the list is scrolled to its end: only then does a streaming answer keep it there.
    @State private var atBottom = true
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
                        // A plain VStack: a lazy one re-estimated the heights of rows while text streamed in,
                        // and the list jumped.
                        VStack(spacing: 18) {
                            ForEach(messages) { message in
                                MessageRow(message: message, chatID: chatID)
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
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
                    } action: { _, bottom in
                        atBottom = bottom
                    }
                    .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                    // A new message (the one you sent): go to the end.
                    .onChange(of: messages.count) {
                        atBottom = true
                        withAnimation(.smooth) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                    }
                    // New text: follow it only while you are at the end; scrolling up stops following.
                    .onChange(of: Self.streamKey(messages.last)) {
                        if atBottom, controller.isStreaming(chatID) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
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
                Composer(chatID: chatID,
                         text: $draft,
                         attachments: $attachments,
                         isDropTarget: dropZone.isTargeted,
                         // Twice as tall, taking in the model picker's row under it (its 28 pt and the 6 pt gap).
                         dropHeight: composerHeight * 2 + 34,
                         isStreaming: controller.isStreaming(chatID),
                         send: send,
                         stop: { controller.stop(chatID) })
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if !dropZone.isTargeted { composerHeight = height }
                    }
                // The model, under the field on the right.
                if !dropZone.isTargeted {
                    HStack {
                        Spacer()
                        ModelPicker(chatID: chatID)
                    }
                    .padding(.trailing, 6)
                    .padding(.top, -4)
                    .transition(.opacity)
                }
            }
            // A little wider than the column of messages.
            .frame(maxWidth: 820)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .onAppear { dropZone.receive = { attachments += $0 } }
        .background(Palette.content)
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

    /// Changes whenever the last answer grows: its text, a step, a tool result.
    private static func streamKey(_ message: Message?) -> Int {
        guard let message else { return 0 }
        return message.content.count + message.steps.reduce(0) { $0 + $1.text.count + $1.calls.filter { $0.result != nil }.count + 1 }
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
