import SwiftUI

/// The connection of one model role: provider, address and token, then the model from the provider's list.
/// The window of Settings → Assistant → Change…, and the body of the onboarding sheet.
struct ModelConnectionEditor: View {
    let role: ModelRole
    var doneTitle = "Save"
    var showsCancel = true
    /// Whether saving closes the sheet it is in (not in the onboarding, which goes on).
    var closes = true
    let done: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var connection: ModelConnection
    @State private var token: String
    @State private var models: [String] = []
    @State private var query = ""
    @State private var loading = false
    @State private var loadError: String?

    init(role: ModelRole, doneTitle: String = "Save", showsCancel: Bool = true, closes: Bool = true, done: @escaping () -> Void = {}) {
        self.role = role
        self.closes = closes
        self.doneTitle = doneTitle
        self.showsCancel = showsCancel
        self.done = done
        let settings = AppSettings.shared
        var connection = settings.connection(role)
        _connection = State(initialValue: connection)
        _token = State(initialValue: settings.token(role))
    }

    private var ownConnection: Bool { role == .chat || !connection.sameAsDefault }

    /// The address and token the list is loaded from.
    private var listEndpoint: (url: URL, token: String)? {
        let settings = AppSettings.shared
        guard let url = AppSettings.normalize(ownConnection ? connection.baseURL : settings.baseURL) else { return nil }
        return (url, ownConnection ? token : settings.token)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if role != .chat {
                        Toggle("Same connection as the default model", isOn: $connection.sameAsDefault)
                    }
                    if ownConnection {
                        Picker("Provider", selection: $connection.provider) {
                            ForEach(ModelProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .onChange(of: connection.provider) { _, provider in
                            if let url = provider.defaultURL { connection.baseURL = url }
                            models = []
                        }
                        TextField("Address", text: $connection.baseURL, prompt: Text(connection.provider.defaultURL ?? "https://…/v1"))
                        SecureField("API Token", text: $token, prompt: Text(connection.provider == .ollama || connection.provider == .lmStudio ? "Not needed" : "sk-…"))
                    }
                } header: {
                    Text("Provider")
                }

                Section {
                    HStack {
                        TextField("Model", text: $connection.model, prompt: Text(role.noneTitle ?? "Model ID"))
                        Button("Load Models", action: load)
                            .disabled(loading || listEndpoint == nil)
                    }
                    if loading { ProgressView().controlSize(.small) }
                    if let loadError {
                        Label(loadError, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .lineLimit(2)
                    }
                    if !models.isEmpty {
                        TextField("Search", text: $query, prompt: Text("Search \(models.count) models"))
                        List(filtered, id: \.self) { id in
                            HStack {
                                Text(id).lineLimit(1)
                                Spacer()
                                if id == connection.model { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                            .contentShape(.rect)
                            .onTapGesture { connection.model = id }
                        }
                        .frame(height: 140)
                    }
                    if let none = role.noneTitle {
                        Button(none) { connection.model = "" }
                            .disabled(connection.model.isEmpty)
                    }
                } header: {
                    Text("Model")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                if showsCancel {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                Button(doneTitle, action: save)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 480, height: models.isEmpty ? 380 : 520)
    }

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? models : models.filter { $0.lowercased().contains(q) }
    }

    private var canSave: Bool {
        if role == .chat {
            return AppSettings.normalize(connection.baseURL) != nil && !connection.model.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !ownConnection || connection.model.isEmpty || AppSettings.normalize(connection.baseURL) != nil
    }

    private func load() {
        guard let endpoint = listEndpoint else { return }
        loading = true
        loadError = nil
        Task {
            defer { loading = false }
            do {
                models = try await OpenAIClient(baseURL: endpoint.url, token: endpoint.token).listModels()
                if models.isEmpty { loadError = "The provider listed no models." }
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private func save() {
        let settings = AppSettings.shared
        settings.setConnection(connection, token: token, for: role)
        if role == .chat {
            for chat in ChatStore.shared.chats where chat.model.isEmpty {
                ChatStore.shared.update(chat.id) { $0.model = settings.defaultModel }
            }
            Task { await ModelStore.shared.refresh() }
        }
        done()
        if closes { dismiss() }
    }
}

/// A role's model in Settings, with a button that opens its editor.
struct ModelRow: View {
    let role: ModelRole
    @State private var editing = false
    private var settings = AppSettings.shared

    init(role: ModelRole) { self.role = role }

    var body: some View {
        let connection = settings.connection(role)
        LabeledContent(role.title) {
            HStack {
                Text(summary(connection))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Change…") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { ModelConnectionEditor(role: role) }
    }

    private func summary(_ connection: ModelConnection) -> String {
        let model = connection.model.trimmingCharacters(in: .whitespaces)
        if model.isEmpty { return role.noneTitle ?? "Not set" }
        let provider = role != .chat && connection.sameAsDefault ? settings.chatProvider : connection.provider
        return "\(model) · \(provider.title)"
    }
}
