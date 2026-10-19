import SwiftUI

/// Base URL, token and model: shared by the onboarding sheet and Settings.
struct ConnectionFields: View {
    @Binding var baseURL: String
    @Binding var token: String
    @Binding var model: String

    @State private var checking = false
    @State private var result: Result<Int, APIError>?
    private var models = ModelStore.shared

    init(baseURL: Binding<String>, token: Binding<String>, model: Binding<String>) {
        _baseURL = baseURL
        _token = token
        _model = model
    }

    var body: some View {
        Section {
            TextField("Base URL", text: $baseURL, prompt: Text(AppSettings.defaultBaseURL))
                .onChange(of: baseURL) { result = nil }
            SecureField("API Token", text: $token, prompt: Text("sk-…"))
                .onChange(of: token) { result = nil }
            HStack {
                Button("Check Connection", action: check)
                    .disabled(checking || AppSettings.normalize(baseURL) == nil || token.isEmpty)
                Spacer()
                status
            }
        } footer: {
            Text("Any OpenAI-compatible server works: OpenAI, OpenRouter, Ollama, LM Studio…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            if !models.models.isEmpty {
                Picker("Model", selection: $model) {
                    if !models.models.contains(model) {
                        Text(model.isEmpty ? "None" : model).tag(model)
                    }
                    ForEach(models.models, id: \.self) { Text($0).tag($0) }
                }
            }
            TextField(models.models.isEmpty ? "Model" : "Model ID", text: $model, prompt: Text("gpt-5"))
        }
    }

    @ViewBuilder
    private var status: some View {
        if checking {
            ProgressView().controlSize(.small)
        } else if case .success(let count)? = result {
            Label("Connected · \(count) models", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else if case .failure(let error)? = result {
            Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(2)
        }
    }

    private func check() {
        guard let url = AppSettings.normalize(baseURL) else { return }
        checking = true
        Task {
            let ok = await models.load(baseURL: url, token: token)
            checking = false
            if ok {
                result = .success(models.models.count)
                if model.isEmpty, let first = models.models.first(where: { $0.contains("gpt") }) ?? models.models.first {
                    model = first
                }
            } else {
                result = .failure(APIError(status: nil, message: models.lastError ?? "Failed", url: nil))
            }
        }
    }
}
