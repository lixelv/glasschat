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
                VStack(alignment: .trailing, spacing: 6) {
                    if !message.attachments.isEmpty {
                        MessageAttachments(attachments: message.attachments)
                    }
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.tint(.accentColor.opacity(0.22)), in: .rect(cornerRadius: 20))
                    }
                }
                .frame(maxWidth: 560, alignment: .trailing)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(message.steps) { step in
                    if !step.text.isEmpty { MarkdownMessage(text: step.text) }
                    ForEach(step.calls) { ToolCallCard(call: $0) }
                }
                if message.isPartial && message.content.isEmpty {
                    // Waiting for the model (also after the tools of a step have answered).
                    if message.steps.last?.calls.allSatisfy({ $0.result != nil }) ?? true { TypingIndicator() }
                } else if !message.content.isEmpty {
                    MarkdownMessage(text: message.content)
                }
                if !message.isPartial {
                    HStack(spacing: 10) {
                        Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Copy answer")
                            .opacity(hovering || copied ? 1 : 0)
                        if let input = message.inputTokens, let output = message.outputTokens {
                            Text("\(input.formatted()) in · \(output.formatted()) out")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Palette.secondaryText)
                                .help("Tokens read and written for this answer")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onHover { hovering = $0 }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        let text = (message.steps.map(\.text) + [message.content]).filter { !$0.isEmpty }.joined(separator: "\n\n")
        NSPasteboard.general.setString(text, forType: .string)
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
