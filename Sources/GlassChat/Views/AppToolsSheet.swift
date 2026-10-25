import SwiftUI

/// The parts of the built-in tools, each with its switch (the same in every chat).
struct AppToolsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var settings = AppSettings.shared
    private var mcp = MCPManager.shared

    private func binding(_ module: AppModule) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledTools.contains(module.key) },
            set: { on in if on { settings.disabledTools.remove(module.key) } else { settings.disabledTools.insert(module.key) } }
        )
    }

    var body: some View {
        let functions = mcp.allFunctions().keys
        VStack(alignment: .leading, spacing: 12) {
            Text("App Tools").font(.headline)
            Text("Tool search and speaking are always on. Tools of a module switched off can still be found by the model's search of every tool.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(AppModule.switchable, id: \.self) { module in
                let count = functions.filter { AppModule.of($0) == module }.count
                Toggle(isOn: binding(module)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(module.title)
                        Text("\(module.summary) · \(count) \(count == 1 ? "tool" : "tools")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
