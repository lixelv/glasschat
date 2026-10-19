import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = AppSettings.shared.baseURL
    @State private var token = AppSettings.shared.token
    @State private var model = AppSettings.shared.defaultModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .padding(18)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .rect(cornerRadius: 22))
                Text("Welcome to GlassChat")
                    .font(.largeTitle.bold())
                Text("Connect to an OpenAI-compatible API to start chatting.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)

            Form {
                ConnectionFields(baseURL: $baseURL, token: $token, model: $model)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 300)

            HStack {
                Spacer()
                Button("Continue", action: save)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 500)
        .interactiveDismissDisabled()
    }

    private var canContinue: Bool {
        AppSettings.normalize(baseURL) != nil && !token.isEmpty && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let settings = AppSettings.shared
        settings.baseURL = baseURL
        settings.token = token
        settings.defaultModel = model.trimmingCharacters(in: .whitespaces)
        for chat in ChatStore.shared.chats where chat.model.isEmpty {
            ChatStore.shared.update(chat.id) { $0.model = settings.defaultModel }
        }
        Task { await ModelStore.shared.refresh() }
        dismiss()
    }
}
