import AVFoundation
import Supertonic
import Speech
import SwiftUI

/// The notch assistant: listening, voice, its prompt.
struct AssistantSettings: View {
    @Bindable private var settings = AppSettings.shared
    @State private var locales: [Locale] = []

    var body: some View {
        Form {
            Section {
                ModelRow(role: .chat)
                ModelRow(role: .decision)
                if settings.endpoint(.decision) != nil {
                    IntField("Tools per search", value: $settings.decisionTopN, range: 1...50)
                }
            } header: {
                Text("Models")
            } footer: {
                footer("New chats and the assistant use the default model; a chat picks its own under the message field. The decision model ranks tools for the tool search; empty: matched by words.")
            }

            Section {
                Toggle("Assistant in the Notch", isOn: $settings.assistantEnabled)
                    .onChange(of: settings.assistantEnabled) { _, _ in
                        NotificationCenter.default.post(name: .assistantToggled, object: nil)
                    }
                ShortcutRecorder()
                    .disabled(!settings.assistantEnabled)
                Toggle("Talk while the pointer is on the notch", isOn: $settings.hoverToTalk)
                    .disabled(!settings.assistantEnabled)
            } header: {
                Text("Notch Assistant")
            } footer: {
                footer("Hold the shortcut and talk: the notch opens into the chat, and letting go sends what you said (nothing, when you said nothing). Or rest the pointer on the notch and talk: it stays compact and answers aloud, opening only when the assistant has something to show or you click it; moving away sends. Talking during an answer silences it. Esc or a click elsewhere folds the notch. Closing the window keeps GlassChat running while this is on.")
            }

            Section {
                RecognitionSettings()
            } header: {
                Text("Speech Recognition")
            } footer: {
                footer("Until Whisper is downloaded, Apple hears.")
            }

            Section {
                Picker("Apple Language", selection: $settings.transcriptionLanguage) {
                    Text("System Languages").tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
                IntField("Messages sent to the model", value: $settings.assistantContextLimit, range: 0...200)
            } header: {
                Text("Listening")
            } footer: {
                footer("System Languages: Apple listens in each language of System Settings (up to three). Messages 0: the whole chat.")
            }

            Section {
                Picker("Voice", selection: $settings.supertonicVoice) {
                    ForEach(Voice.allCases, id: \.self) { voice in
                        Text(Self.voiceName(voice)).tag(voice.rawValue)
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                footer("Supertonic 3 speaks on this Mac in the language of each text; until it is downloaded, the macOS voice does.")
            }

            Section {
                VoiceModelsStatus()
            } header: {
                Text("Voice Models")
            }

            Section {
                Picker("Confirm Actions", selection: $settings.confirmActions) {
                    ForEach(ConfirmMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Files and Terminal")
            } footer: {
                footer("Before app_write, app_edit and app_bash. In Auto the decision model judges each action and asks you about what it does not call safe — text the model read in files or on websites can sway it. Without a decision model, Auto always asks.")
            }

            Section {
                TextEditor(text: $settings.assistantPrompt)
                    .font(.body)
                    .frame(minHeight: 180)
                HStack {
                    Spacer()
                    Button("Reset") { settings.assistantPrompt = AssistantPrompt.standard }
                        .disabled(settings.assistantPrompt == AssistantPrompt.standard)
                }
            } header: {
                Text("Assistant Prompt")
            } footer: {
                footer("Sent after the system prompt in the assistant's chat.")
            }
        }
        .formStyle(.grouped)
        .task {
            locales = await DictationTranscriber.supportedLocales.sorted {
                (Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier)
                    < (Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier)
            }
        }
    }

    /// "Female 1" for F1.
    private static func voiceName(_ voice: Voice) -> String {
        let raw = voice.rawValue
        return (raw.hasPrefix("F") ? "Female " : "Male ") + raw.dropFirst()
    }

    private func footer(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

/// A number to type into, and the arrows beside it (as "Tools per search").
private struct NumberField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("", value: $value, format: .number.precision(.fractionLength(0...1)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .onChange(of: value) { _, v in value = min(max(v, range.lowerBound), range.upperBound) }
                Text(unit).foregroundStyle(.secondary)
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

private struct IntField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    init(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) {
        self.title = title
        _value = value
        self.range = range
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("", value: $value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .onChange(of: value) { _, v in value = min(max(v, range.lowerBound), range.upperBound) }
                Stepper("", value: $value, in: range)
                    .labelsHidden()
            }
        }
    }
}

extension Notification.Name {
    /// The notch assistant was switched on or off in Settings.
    static let assistantToggled = Notification.Name("GlassChat.assistantToggled")
}
