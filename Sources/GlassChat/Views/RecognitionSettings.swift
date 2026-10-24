import SwiftUI

/// Apple or Whisper, and the state of the two local voice models.
/// In Settings → Assistant and in the onboarding sheet.
struct RecognitionSettings: View {
    @Bindable private var settings = AppSettings.shared

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
    }
}

/// Download state of Whisper and Supertonic, with a retry.
struct VoiceModelsStatus: View {
    private var models = VoiceModels.shared

    var body: some View {
        row("Whisper large-v3-turbo (hearing, ~630 MB)", models.whisper)
        row("Supertonic 3 (voice, ~400 MB)", models.speech)
        if case .failed = models.whisper { retry } else if case .failed = models.speech { retry }
    }

    private var retry: some View {
        HStack {
            Spacer()
            Button("Download Again") { Task { await models.downloadAll() } }
        }
    }

    private func row(_ title: String, _ state: VoiceModels.State) -> some View {
        LabeledContent(title) {
            switch state {
            case .missing:
                Text("Not downloaded").foregroundStyle(.secondary)
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 120)
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill").foregroundStyle(.red).lineLimit(2)
            }
        }
    }
}
