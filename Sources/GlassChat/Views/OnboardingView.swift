import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

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

            ModelConnectionEditor(role: .chat, doneTitle: "Continue", showsCancel: false)
        }
        .frame(width: 480)
        .interactiveDismissDisabled()
    }
}
