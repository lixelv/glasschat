import SwiftUI

struct ModelPicker: View {
    let chatID: Chat.ID
    @State private var askingCustom = false
    @State private var custom = ""
    private var store = ChatStore.shared
    private var models = ModelStore.shared
    private var settings = AppSettings.shared

    init(chatID: Chat.ID) { self.chatID = chatID }

    private var current: String {
        let model = store.chat(chatID)?.model ?? ""
        return model.isEmpty ? settings.defaultModel : model
    }

    var body: some View {
        Menu {
            if models.models.isEmpty {
                Text(models.isLoading ? "Loading models…" : (models.lastError ?? "No models"))
            } else {
                ForEach(models.models, id: \.self) { model in
                    Toggle(model, isOn: Binding(get: { model == current }, set: { _ in choose(model) }))
                }
            }
            Divider()
            Button("Other Model…") {
                custom = current
                askingCustom = true
            }
            Button("Refresh List") { Task { await models.refresh() } }
        } label: {
            Label(current.isEmpty ? "Choose Model" : current, systemImage: "cpu")
                .font(.callout.weight(.medium))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Model of this chat")
        .task { if models.models.isEmpty { await models.refresh() } }
        .alert("Model ID", isPresented: $askingCustom) {
            TextField("e.g. gpt-5", text: $custom)
            Button("Use") {
                let id = custom.trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty { choose(id) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func choose(_ model: String) {
        store.update(chatID) { $0.model = model }
        settings.defaultModel = model
    }
}
