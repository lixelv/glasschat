import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    /// First the default model, then how speech is recognised.
    @State private var step = 0

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

            if step == 0 {
                ModelConnectionEditor(role: .chat, doneTitle: "Continue", showsCancel: false, closes: false) { step = 1 }
            } else {
                Form {
                    Section {
                        RecognitionSettings()
                    } header: {
                        Text("How should the assistant hear you?")
                    } footer: {
                        Text("You can change it later in Settings → Assistant.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .frame(height: 380)
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
        }
        .frame(width: 480)
        .interactiveDismissDisabled()
    }
}
