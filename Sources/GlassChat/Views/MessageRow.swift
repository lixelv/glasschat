import AppKit
import SwiftUI

struct MessageRow: View {
    let message: Message
    let chatID: Chat.ID
    @Environment(ChatController.self) private var controller
    @State private var hovering = false
    @State private var copied = false
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 6) {
                    if !message.attachments.isEmpty {
                        MessageAttachments(attachments: message.attachments)
                    }
                    if editing {
                        editor
                    } else {
                        if !message.content.isEmpty {
                            Text(message.content)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .glassEffect(.regular.tint(.accentColor.opacity(0.22)), in: .rect(cornerRadius: 20))
                        }
                        HStack(spacing: 12) {
                            action(copied ? "Copied" : "Copy", copied ? "checkmark" : "doc.on.doc", copy)
                            action("Edit", "pencil") { draft = message.content; editing = true }
                            action("Retry from Here", "arrow.clockwise") {
                                controller.resend(from: message.id, text: message.content, attachments: message.attachments, in: chatID)
                            }
                            action("Branch from Here", "arrow.triangle.branch") { controller.branch(chatID, through: message.id) }
                        }
                        // Not 0: a fully transparent view leaves the accessibility tree (VoiceOver could not reach it).
                        .opacity(hovering || copied ? 1 : 0.001)
                    }
                }
                .frame(maxWidth: editing ? .infinity : 560, alignment: .trailing)
            }
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .contextMenu { menu }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(message.steps) { step in
                    if !step.text.isEmpty { MarkdownMessage(text: step.text) }
                    if !step.calls.isEmpty { ToolCallsGroup(calls: step.calls) }
                }
                if message.isPartial && message.content.isEmpty {
                    // Waiting for the model (also after the tools of a step have answered).
                    if message.steps.last?.calls.allSatisfy({ $0.result != nil }) ?? true { TypingIndicator() }
                } else if !message.content.isEmpty {
                    MarkdownMessage(text: message.content)
                }
                if !message.isPartial {
                    HStack(spacing: 10) {
                        HStack(spacing: 12) {
                            action(copied ? "Copied" : "Copy", copied ? "checkmark" : "doc.on.doc", copy)
                            action("Branch from Here", "arrow.triangle.branch") { controller.branch(chatID, through: message.id) }
                        }
                        // Not 0: a fully transparent view leaves the accessibility tree (VoiceOver could not reach it).
                        .opacity(hovering || copied ? 1 : 0.001)
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
            // Its parts stay separate elements (the tools button is not the whole answer).
            .accessibilityElement(children: .contain)
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .contextMenu { menu }
        }
    }

    /// The same actions on a right click.
    @ViewBuilder private var menu: some View {
        Button("Copy", systemImage: "doc.on.doc", action: copy)
        if message.role == .user {
            Button("Edit", systemImage: "pencil") { draft = message.content; editing = true }
            Button("Retry from Here", systemImage: "arrow.clockwise") {
                controller.resend(from: message.id, text: message.content, attachments: message.attachments, in: chatID)
            }
        }
        Button("Branch from Here", systemImage: "arrow.triangle.branch") { controller.branch(chatID, through: message.id) }
    }

    /// An icon button of the row's hover bar; its name is the tooltip.
    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(title, systemImage: icon, action: run)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(title)
    }

    /// The message being edited: sending it restarts the conversation from here.
    private var editor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 240)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .glassEffect(.regular.tint(.accentColor.opacity(0.22)), in: .rect(cornerRadius: 20))
            HStack {
                Text("The answers after this message are replaced.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
                Button("Cancel") { editing = false }
                    .keyboardShortcut(.cancelAction)
                Button("Send") {
                    editing = false
                    controller.resend(from: message.id, text: draft, attachments: message.attachments, in: chatID)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.attachments.isEmpty)
            }
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
