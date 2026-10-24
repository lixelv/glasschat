import AVFoundation
import Speech
import SwiftUI

/// The notch assistant: listening, voice, its prompt.
struct AssistantSettings: View {
    @Bindable private var settings = AppSettings.shared
    @State private var locales: [Locale] = []
    @State private var advanced = false

    var body: some View {
        Form {
            Section {
                ModelRow(role: .chat)
                ModelRow(role: .decision)
                if settings.endpoint(.decision) != nil {
                    IntField("Tools per search", value: $settings.decisionTopN, range: 1...50)
                }
                ModelRow(role: .speech)
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
            } header: {
                Text("Notch Assistant")
            } footer: {
                footer("Click the notch or press the shortcut to talk; the shortcut again folds it. Closing the window keeps GlassChat running while this is on.")
            }

            Section {
                RecognitionSettings()
            } header: {
                Text("Speech Recognition")
            }

            Section {
                Picker("Language", selection: $settings.transcriptionLanguage) {
                    Text("System Languages").tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
                NumberField("Pause that ends a phrase", value: $settings.silencePause, range: 0.5...5, step: 0.1, unit: "s")
                NumberField("Keep listening after an answer", value: $settings.followUpWindow, range: 0...60, step: 1, unit: "s")
                IntField("Messages sent to the model", value: $settings.assistantContextLimit, range: 0...200)
            } header: {
                Text("Listening")
            } footer: {
                footer("System Languages: Apple listens in each language of System Settings (up to three) and keeps the surest. Messages 0: the whole chat.")
            }

            Section {
                Picker("macOS Voice", selection: $settings.systemVoice) {
                    Text("System Default").tag("")
                    ForEach(Self.voices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                    }
                }
                .disabled(settings.endpoint(.speech) != nil)
                if settings.endpoint(.speech) != nil {
                    TextField("Voice of the Speech Model", text: $settings.ttsVoice, prompt: Text("alloy"))
                }
            } header: {
                Text("Voice")
            } footer: {
                footer("Without a speech model: the macOS voice. Texts in another language than the chosen voice get a voice of their own language.")
            }

            Section {
                TextEditor(text: $settings.assistantPrompt)
                    .font(.body)
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if settings.assistantPrompt.isEmpty {
                            Text(AssistantPrompt.standard)
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                HStack {
                    Spacer()
                    Button("Reset") { settings.assistantPrompt = "" }
                        .disabled(settings.assistantPrompt.isEmpty)
                }
            } header: {
                Text("Assistant Prompt")
            } footer: {
                footer("Sent after the system prompt in the assistant's chat.")
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    NumberField("Wait for speech after a click", value: $settings.speechWait, range: 2...30, step: 1, unit: "s")
                }
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

    private static let voices = AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) }

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
