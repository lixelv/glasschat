import SwiftUI

/// A glass button with the chat's model; opens a searchable list (OpenRouter offers hundreds).
struct ModelPicker: View {
    let chatID: Chat.ID
    @State private var open = false
    private var store = ChatStore.shared
    private var settings = AppSettings.shared

    init(chatID: Chat.ID) { self.chatID = chatID }

    private var current: String {
        let model = store.chat(chatID)?.model ?? ""
        return model.isEmpty ? settings.defaultModel : model
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                Text(current.isEmpty ? "Choose Model" : current)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.callout.weight(.medium))
        }
        .buttonStyle(.glass)
        .fixedSize()
        .help("Model of this chat")
        .popover(isPresented: $open, arrowEdge: .top) {
            ModelSearchList(current: current) { model in
                store.update(chatID) { $0.model = model }
                settings.defaultModel = model
                open = false
            }
        }
    }
}

private struct ModelSearchList: View {
    let current: String
    let choose: (String) -> Void

    @State private var query = ""
    @State private var highlighted: String?
    @FocusState private var searchFocused: Bool
    private var models = ModelStore.shared

    init(current: String, choose: @escaping (String) -> Void) {
        self.current = current
        self.choose = choose
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Every word of the query must occur in the id, so "claude sonnet" finds "anthropic/claude-sonnet-4".
    private var matches: [String] {
        let words = trimmed.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return models.models }
        return models.models.filter { id in
            let id = id.lowercased()
            return words.allSatisfy { id.contains($0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search models", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit(submit)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                if models.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await models.refresh() } }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Refresh the list")
                }
            }
            .padding(10)
            .glassEffect(.regular, in: .capsule)
            .padding(10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if !trimmed.isEmpty && !models.models.contains(trimmed) {
                            row(trimmed, title: "Use “\(trimmed)”", icon: "return")
                        }
                        ForEach(matches, id: \.self) { model in
                            row(model, title: model, icon: model == current ? "checkmark" : nil)
                        }
                        if matches.isEmpty && trimmed.isEmpty {
                            Text(models.isLoading ? "Loading models…" : (models.lastError ?? "No models"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(12)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: highlighted) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
                .onAppear { proxy.scrollTo(current, anchor: .center) }
            }
            Divider()
            Text("\(matches.count) of \(models.models.count) models")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: 380, height: 440)
        .onAppear { searchFocused = true }
        .onChange(of: query) { highlighted = nil }
        .task { if models.models.isEmpty { await models.refresh() } }
    }

    private func row(_ model: String, title: String, icon: String?) -> some View {
        Button { choose(model) } label: {
            HStack {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(.rect)
            .background(highlighted == model ? Color.accentColor.opacity(0.18) : .clear,
                        in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .id(model)
    }

    private var choices: [String] {
        (!trimmed.isEmpty && !models.models.contains(trimmed) ? [trimmed] : []) + matches
    }

    private func move(_ step: Int) {
        let list = choices
        guard !list.isEmpty else { return }
        let i = highlighted.flatMap { list.firstIndex(of: $0) } ?? (step > 0 ? -1 : list.count)
        highlighted = list[min(max(i + step, 0), list.count - 1)]
    }

    private func submit() {
        if let pick = highlighted ?? matches.first ?? (trimmed.isEmpty ? nil : trimmed) { choose(pick) }
    }
}
