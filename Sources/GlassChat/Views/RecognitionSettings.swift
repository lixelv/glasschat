import SwiftUI

/// How speech becomes the assistant's message: the four ways, and what each needs (a model, an install).
/// In Settings → Assistant and in the onboarding sheet.
struct RecognitionSettings: View {
    @Bindable private var settings = AppSettings.shared
    private var whisper = LocalWhisper.shared

    var body: some View {
        Picker("Speech Recognition", selection: $settings.recognitionMode) {
            ForEach(RecognitionMode.allCases, id: \.self) { mode in
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                    Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                }
                .tag(mode)
            }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
        .onChange(of: settings.recognitionMode) { _, mode in
            if mode == .localWhisper { whisper.refresh() }
        }
        .onAppear { whisper.refresh() }

        switch settings.recognitionMode {
        case .provider:
            ModelRow(role: .transcription)
        case .localWhisper:
            whisperRow
        case .builtIn, .audioToModel:
            EmptyView()
        }
    }

    @ViewBuilder private var whisperRow: some View {
        HStack {
            switch whisper.state {
            case .checking:
                ProgressView().controlSize(.small)
            case .needsHomebrew:
                Text("Homebrew is not installed. Install opens Terminal (it asks for your password), then press Install again.")
                    .font(.callout).foregroundStyle(.secondary)
            case .needsInstall:
                Text("whisper.cpp and the model (about 550 MB) are not installed yet.")
                    .font(.callout).foregroundStyle(.secondary)
            case .installing(let step):
                ProgressView().controlSize(.small)
                Text(step).font(.callout).foregroundStyle(.secondary)
            case .downloading(let fraction):
                ProgressView("Downloading the model…", value: fraction).font(.callout)
            case .ready:
                Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill").foregroundStyle(.red).lineLimit(3)
            }
            Spacer()
            switch whisper.state {
            case .needsHomebrew, .needsInstall, .failed:
                Button("Install") { Task { await whisper.install() } }
            default:
                EmptyView()
            }
        }
    }
}
