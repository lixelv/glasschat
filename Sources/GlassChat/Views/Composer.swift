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

    @FocusState private var focused: Bool

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
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        Button("Attach Files", systemImage: "paperclip", action: pickFiles)
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 32)
                            .help("Attach files")

                        TextField("Message", text: $text, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .lineLimit(1...8)
                            .focused($focused)
                            .padding(.vertical, 7)
                            .onKeyPress(.return, phases: .down) { press in
                                if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                                    text += "\n"
                                    return .handled
                                }
                                if !isStreaming && canSend { send() }
                                return .handled
                            }
                            .onPasteCommand(of: [.fileURL, .image], perform: paste)

                        ToolsButton(chatID: chatID)

                        Button(action: isStreaming ? stop : send) {
                            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                                .font(.body.weight(.semibold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
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
        .onAppear { focused = true }
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

    /// ⌘V of a file or a picture attaches it; plain text is pasted by the field itself.
    private func paste(_ providers: [NSItemProvider]) {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            add(urls)
        } else if let image = NSImage(pasteboard: pasteboard), let attachment = try? AttachmentStore.importImage(image) {
            withAnimation(.snappy) { attachments.append(attachment) }
        }
    }
}

/// The MCP servers of this chat: how many tools are on, and switches per server.
private struct ToolsButton: View {
    let chatID: Chat.ID
    @State private var open = false
    @Environment(\.openSettings) private var openSettings
    private var mcp = MCPManager.shared
    private var store = ChatStore.shared

    init(chatID: Chat.ID) { self.chatID = chatID }

    var body: some View {
        let disabled = store.chat(chatID)?.disabledServers ?? []
        let count = mcp.activeToolCount(disabled: disabled)
        let enabled = mcp.servers.filter(\.enabled)
        if !enabled.isEmpty {
            Button { open.toggle() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "hammer")
                    if count > 0 { Text("\(count)").font(.caption.monospacedDigit()) }
                }
                .frame(height: 32)
                .foregroundStyle(count > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help("MCP tools of this chat")
            .popover(isPresented: $open, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tools").font(.headline)
                    ForEach(enabled) { server in
                        Toggle(isOn: Binding(
                            get: { !(store.chat(chatID)?.disabledServers.contains(server.id) ?? false) },
                            set: { on in store.update(chatID) { if on { $0.disabledServers.remove(server.id) } else { $0.disabledServers.insert(server.id) } } }
                        )) {
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
                .frame(width: 280)
            }
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
