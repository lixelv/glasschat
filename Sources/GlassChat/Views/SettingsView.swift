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
