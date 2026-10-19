import AppKit
import SwiftUI

struct MessageRow: View {
    let message: Message
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 80)
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.22)), in: .rect(cornerRadius: 20))
                    .frame(maxWidth: 560, alignment: .trailing)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if message.isPartial && message.content.isEmpty {
                    TypingIndicator()
                } else {
                    MarkdownMessage(text: message.content)
                }
                if !message.isPartial {
                    Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Copy answer")
                        .opacity(hovering || copied ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onHover { hovering = $0 }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

private struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 7, height: 7)
                    .phaseAnimator([0.3, 1.0]) { dot, phase in
                        dot.opacity(phase)
                    } animation: { _ in .easeInOut(duration: 0.6).delay(Double(i) * 0.2) }
            }
        }
        .padding(.vertical, 6)
    }
}
