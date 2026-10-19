import SwiftUI

/// Settings → MCP: the servers, a switch each, their status, and an editor sheet.
struct MCPSettings: View {
    @State private var editing: MCPServer?
    @State private var isNew = false
    private var mcp = MCPManager.shared

    var body: some View {
        Form {
            Section {
                if mcp.servers.isEmpty {
                    Text("No servers yet. Add a local (stdio) server such as `npx -y @modelcontextprotocol/server-filesystem ~/Documents`, or a remote one by its URL.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(mcp.servers) { server in
                    HStack(spacing: 10) {
                        Image(systemName: server.transport == .stdio ? "terminal" : "globe")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                            MCPStatusLine(server: server)
                        }
                        Spacer()
                        Button("Edit") { isNew = false; editing = server }
                        Toggle("Enabled", isOn: Binding(
                            get: { server.enabled },
                            set: { var s = server; s.enabled = $0; mcp.update(s) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .contextMenu {
                        Button("Reconnect") { mcp.reconnect(server.id) }
                        Button("Delete", role: .destructive) { mcp.remove(server.id) }
                    }
                }
            } header: {
                HStack {
                    Text("Servers")
                    Spacer()
                    Button("Add Server", systemImage: "plus") {
                        isNew = true
                        editing = MCPServer(name: "New Server")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text("Enabled servers are on in every chat; the hammer button in a chat switches them off there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { server in
            MCPServerEditor(server: server, isNew: isNew) { saved in
                if isNew { mcp.add(saved) } else { mcp.update(saved) }
            } delete: {
                mcp.remove(server.id)
            }
        }
    }
}

private struct MCPServerEditor: View {
    @State var server: MCPServer
    let isNew: Bool
    let save: (MCPServer) -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $server.name)
                    Picker("Type", selection: $server.transport) {
                        Text("Local (stdio)").tag(MCPServer.Transport.stdio)
                        Text("Remote (HTTP)").tag(MCPServer.Transport.http)
                    }
                    .pickerStyle(.segmented)
                }
                switch server.transport {
                case .stdio:
                    Section {
                        TextField("Command", text: $server.command, prompt: Text("npx -y @modelcontextprotocol/server-filesystem ~/Documents"))
                            .font(.system(.body, design: .monospaced))
                    } footer: {
                        Text("Run through your login shell, so npx, uvx and the rest of your PATH work.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Environment (KEY=value per line)") {
                        TextEditor(text: $server.environment)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 70)
                    }
                case .http:
                    Section {
                        TextField("URL", text: $server.url, prompt: Text("https://example.com/mcp"))
                    }
                    Section("Headers (Name: value per line)") {
                        TextEditor(text: $server.headers)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 70)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { delete(); dismiss() }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save(server); dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(server.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 440)
    }
}
