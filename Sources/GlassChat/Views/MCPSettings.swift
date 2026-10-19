import SwiftUI

/// Settings → MCP: the `mcpServers` JSON (as in Claude Desktop), and the state of each server.
struct MCPSettings: View {
    @State private var text = MCPManager.shared.configText
    @State private var error: String?
    private var mcp = MCPManager.shared

    private var changed: Bool { text != mcp.configText }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(error == nil ? Color.secondary.opacity(0.2) : .red.opacity(0.6)))

            HStack(alignment: .firstTextBaseline) {
                if let error {
                    Label(error, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .lineLimit(2)
                } else {
                    Text("`command` + `args` + `env` for a local server, `url` + `headers` for a remote one; `\"disabled\": true` keeps it off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Revert") { text = mcp.configText; error = nil }
                    .disabled(!changed)
                Button("Apply", action: apply)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("s")
                    .disabled(!changed)
            }

            if !mcp.servers.isEmpty || !mcp.configErrors.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(mcp.servers) { server in
                            HStack(spacing: 8) {
                                Image(systemName: server.transport == .stdio ? "terminal" : "globe")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(server.name).font(.callout.weight(.medium))
                                MCPStatusLine(server: server)
                                Spacer()
                                Button("Reconnect", systemImage: "arrow.clockwise") { mcp.reconnect(server.id) }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .disabled(!server.enabled)
                            }
                        }
                        ForEach(mcp.configErrors, id: \.self) { message in
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
        }
        .padding(16)
        .onChange(of: mcp.configText) { _, new in
            // The model may have edited the registry: show it unless there are unsaved edits.
            if error == nil, !changed || text == new { text = new }
        }
    }

    private func apply() {
        do {
            try mcp.apply(text)
            text = mcp.configText
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
