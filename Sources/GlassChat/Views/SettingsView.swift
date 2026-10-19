import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Connection", systemImage: "network") { ConnectionSettings() }
            Tab("Prompt", systemImage: "text.bubble") { PromptSettings() }
            Tab("MCP", systemImage: "hammer") { MCPSettings() }
        }
        .frame(width: 600, height: 460)
    }
}

private struct ConnectionSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            ConnectionFields(baseURL: $settings.baseURL, token: $settings.token, model: $settings.defaultModel)
            DecisionSettings()
        }
        .formStyle(.grouped)
    }
}

private struct PromptSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 220)
            } header: {
                Text("System Prompt")
            } footer: {
                Text("Sent at the start of every chat that has no prompt of its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// The decision model that ranks tools for the model's tool search.
private struct DecisionSettings: View {
    @Bindable private var settings = AppSettings.shared
    @State private var editingConnection = false

    var body: some View {
        Section {
            TextField("Decision Model", text: $settings.decisionModel, prompt: Text("typesafe/jev-1.14"))
            // A field to type into, and the arrows beside it.
            LabeledContent("Tools per search") {
                HStack(spacing: 4) {
                    TextField("", value: $settings.decisionTopN, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                        .onChange(of: settings.decisionTopN) { _, n in
                            if n < 1 { settings.decisionTopN = 1 } else if n > 50 { settings.decisionTopN = 50 }
                        }
                    Stepper("", value: $settings.decisionTopN, in: 1...50)
                        .labelsHidden()
                }
            }
            HStack {
                Text(settings.decisionBaseURL.isEmpty && settings.decisionToken.isEmpty
                     ? "Same base URL and token as the chat" : "Own base URL or token")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Connection…") { editingConnection = true }
            }
        } header: {
            Text("Tool Search")
        } footer: {
            Text("The model searches the tools that are switched off instead of getting all of them. A decision model (such as Jev) ranks them; empty: matched by words.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $editingConnection) {
            DecisionConnectionSheet()
        }
    }
}

private struct DecisionConnectionSheet: View {
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Base URL", text: $settings.decisionBaseURL, prompt: Text(settings.baseURL))
                    SecureField("API Token", text: $settings.decisionToken, prompt: Text("Same as the chat"))
                } header: {
                    Text("Decision Model Connection")
                } footer: {
                    Text("Empty fields use the chat's. Decisions are asked at <base without /v1>/alpha/decisions (OpenRouter).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Use the Chat's") {
                    settings.decisionBaseURL = ""
                    settings.decisionToken = ""
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460, height: 280)
    }
}
