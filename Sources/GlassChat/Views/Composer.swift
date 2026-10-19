import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct Composer: View {
    let chatID: Chat.ID
    @Binding var text: String
    @Binding var attachments: [Attachment]
    /// Files are dragged over the window: the composer grows into a drop zone.
    let isDropTarget: Bool
    /// The height to grow to while files are dragged over the window.
    let dropHeight: CGFloat
    let isStreaming: Bool
    let send: () -> Void
    let stop: () -> Void

    @State private var editorHeight: CGFloat = 34

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var body: some View {
        GlassEffectContainer {
            ZStack {
                VStack(alignment: .leading, spacing: 8) {
                    if !attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(attachments) { attachment in
                                    AttachmentChip(attachment: attachment) {
                                        withAnimation(.snappy) { attachments.removeAll { $0.id == attachment.id } }
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                        .padding(.leading, 4)
                    }
                    // The paperclip stays in the middle; the send button grows with the text.
                    HStack(alignment: .center, spacing: 8) {
                        Button("Attach Files", systemImage: "paperclip", action: pickFiles)
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .help("Attach files")

                        MessageEditor(text: $text, height: $editorHeight, submit: {
                            if !isStreaming && canSend { send() }
                        }, attachFiles: add, attachImage: { image in
                            if let attachment = try? AttachmentStore.importImage(image) {
                                withAnimation(.snappy) { attachments.append(attachment) }
                            }
                        })
                        .frame(height: editorHeight)

                        ToolsButton(chatID: chatID)

                        Button(action: isStreaming ? stop : send) {
                            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                                .font(.body.weight(.semibold))
                                .frame(width: 18, height: max(18, editorHeight - 16))
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .disabled(!isStreaming && !canSend)
                        .help(isStreaming ? "Stop" : "Send")
                    }
                }
                .opacity(isDropTarget ? 0 : 1)

                if isDropTarget {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 26, weight: .light))
                        Text("Drop files here")
                            .font(.headline)
                    }
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                    .transition(.opacity)
                }
            }
            .frame(height: isDropTarget ? dropHeight - 12 : nil)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .glassEffect(isDropTarget ? .regular.tint(.accentColor.opacity(0.18)).interactive() : .regular.interactive(),
                         in: .rect(cornerRadius: 24))
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func add(_ urls: [URL]) {
        let imported = urls.compactMap { try? AttachmentStore.importFile(at: $0) }
        withAnimation(.snappy) { attachments += imported }
    }
}

/// The MCP servers of this chat: how many tools are on, and switches for the registry tools and each server.
private struct ToolsButton: View {
    let chatID: Chat.ID
    @State private var open = false
    @Environment(\.openSettings) private var openSettings
    private var mcp = MCPManager.shared
    private var settings = AppSettings.shared

    init(chatID: Chat.ID) { self.chatID = chatID }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledTools.contains(key) },
            set: { on in if on { settings.disabledTools.remove(key) } else { settings.disabledTools.insert(key) } }
        )
    }

    var body: some View {
        let disabled = settings.disabledTools
        let count = mcp.activeToolCount(disabled: disabled)
        Button { open.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: "hammer")
                if count > 0 { Text("\(count)").font(.caption.monospacedDigit()) }
            }
            .frame(height: 28)
            .foregroundStyle(count > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .help("Tools")
        .popover(isPresented: $open, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tools").font(.headline)
                Text("Switches are the same in every chat. Tools switched off can still be found by the model's tool search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: binding(AppTool.key)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("App")
                        Text("Built in: notifications, alerts, chats, models, MCP servers and their registry")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                ForEach(mcp.servers.filter(\.enabled)) { server in
                    Toggle(isOn: binding(server.id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(server.name)
                            MCPStatusLine(server: server)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                }
                Divider()
                Button("MCP Settings…") { open = false; openSettings() }
                    .buttonStyle(.link)
            }
            .padding(16)
            .frame(width: 300)
        }
    }
}

/// "12 tools", "Connecting…" or the error of a server.
struct MCPStatusLine: View {
    let server: MCPServer
    private var mcp = MCPManager.shared

    init(server: MCPServer) { self.server = server }

    var body: some View {
        Group {
            switch mcp.status[server.id] ?? .off {
            case .off: Text("Off")
            case .connecting: Text("Connecting…")
            case .connected:
                let n = mcp.tools[server.id]?.count ?? 0
                Text("\(n) \(n == 1 ? "tool" : "tools")").foregroundStyle(.green)
            case .failed(let message): Text(message).foregroundStyle(.red).lineLimit(2)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
