import SwiftUI

struct ChatView: View {
    let chatID: Chat.ID

    @Environment(ChatController.self) private var controller
    @State private var draft = ""
    @State private var attachments: [Attachment] = []
    @Environment(DropZone.self) private var dropZone
    @State private var composerHeight: CGFloat = 46
    /// The height of everything under the messages (composer, model row): the messages fade out above it.
    @State private var insetHeight: CGFloat = 0
    @State private var showPrompt = false
    @State private var viewportHeight: CGFloat = 0
    /// Whether the list keeps to its end as the answer grows; scrolling up stops it, back to the end resumes it.
    @State private var following = true
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var scrollPhase: ScrollPhase = .idle
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
                ScrollView {
                    // Messages start at the top; the column is at least as tall as the view,
                    // so the ScrollView never has bare space of its own (it lit up under the pointer).
                    // Older messages are lazy (only those on screen are made: a long chat scrolls smoothly);
                    // the last ones are not: a lazy row re-estimated its height while text streamed in,
                    // and the list jumped.
                    let (settled, recent) = Self.split(messages.map(\.id), recent: 2)
                    let byID = Self.index(messages)
                    VStack(spacing: 18) {
                        LazyVStack(spacing: 18) {
                            ForEach(settled, id: \.self) { id in
                                if let message = byID[id] { MessageRow(message: message, chatID: chatID).id(id) }
                            }
                        }
                        ForEach(recent, id: \.self) { id in
                            if let message = byID[id] { MessageRow(message: message, chatID: chatID).id(id) }
                        }
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                    .contentShape(.rect)
                }
                .scrollPosition($position)
                .onGeometryChange(for: CGFloat.self) { $0.size.height - 32 } action: { viewportHeight = max($0, 0) }
                // Only your own scrolling switches following. The answer's height is not steady while it
                // streams (formulas and code blocks are laid out again, tool cards come in), and the scroll
                // view moves its offset by itself when it shrinks; reading that as "scrolled away" stopped
                // the list from following, and the answer ran on out of sight below.
                .onScrollPhaseChange { old, phase, context in
                    scrollPhase = phase
                    if phase.isScrolling || old.isScrolling {
                        following = context.geometry.distanceToBottom <= 40
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.distanceToBottom } action: { _, distance in
                    if scrollPhase.isScrolling {
                        following = distance <= 40
                    } else if following, scrollPhase == .idle, distance > 0.5 {
                        position.scrollTo(edge: .bottom)
                    }
                }
                .onAppear { position.scrollTo(edge: .bottom) }
                // A new message (the one you sent): go to the end and follow the answer.
                .onChange(of: messages.count) {
                    following = true
                    withAnimation(.smooth) { position.scrollTo(edge: .bottom) }
                }
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .top)
                // Web pages (visualizations) are drawn above the composer's glass, not behind it: the messages
                // fade out where the composer starts instead of running under it.
                .mask {
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
                        Color.clear.frame(height: max(insetHeight - 16, 0))
                    }
                    .ignoresSafeArea()
                }
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
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { insetHeight = $0 }
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

    /// The messages by id; a damaged file with one id twice keeps the first.
    static func index(_ messages: [Message]) -> [Message.ID: Message] {
        Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The messages laid out lazily and the last `recent` ones laid out always.
    static func split<ID>(_ ids: [ID], recent: Int) -> (settled: [ID], recent: [ID]) {
        let cut = max(ids.count - recent, 0)
        return (Array(ids[..<cut]), Array(ids[cut...]))
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

private extension ScrollGeometry {
    /// How far the visible part is from the end of the content.
    var distanceToBottom: CGFloat {
        contentSize.height + contentInsets.bottom - (contentOffset.y + containerSize.height)
    }
}

private extension ScrollPhase {
    /// You are moving the list: dragging, flicking, or it still glides after your flick.
    var isScrolling: Bool { self == .interacting || self == .decelerating || self == .tracking }
}
