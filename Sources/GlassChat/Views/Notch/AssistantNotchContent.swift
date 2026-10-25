import AppKit
import SwiftUI

/// The body of the expanded notch: the last exchange with the assistant, its tools, a question card, and controls.
struct AssistantNotchContent: View {
    private var assistant = AssistantController.shared
    private var store = ChatStore.shared
    @State private var bodyHeight: CGFloat = 0

    /// The height left under the notch row for the scrolling part (the buttons take the rest).
    private var maxBody: CGFloat { NotchPanelController.shared.model.maxHeight - 32 - 44 }

    var body: some View {
        let id = assistant.chatID
        let messages = store.chat(id)?.messages ?? []
        let answer = messages.last.flatMap { $0.role == .assistant ? $0 : nil }
        let question = messages.last(where: { $0.role == .user })

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let said = assistant.heard.isEmpty ? (question?.content ?? "") : assistant.heard
                    if !said.isEmpty {
                        Text(said)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.55))
                    } else if answer == nil {
                        Text(listeningHint)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    if let progress = assistant.downloadProgress {
                        ProgressView("Downloading the speech model…", value: progress)
                            .font(.caption)
                    }
                    if let answer {
                        let calls = answer.steps.flatMap(\.calls)
                        if !calls.isEmpty { ToolChips(calls: calls) }
                        let text = (answer.steps.map(\.text) + [answer.content]).filter { !$0.isEmpty }.joined(separator: "\n\n")
                        if !text.isEmpty { MarkdownMessage(text: text, compact: true) }
                        if let visualization = calls.filter({ $0.result != nil }).compactMap(Visualization.init).last {
                            VisualizationView(visualization, maxHeight: .infinity, dark: true)
                        }
                    }
                    if QuestionCenter.shared.pending[id] != nil {
                        QuestionCard(chatID: id)
                    }
                    if ApprovalCenter.shared.pending[id] != nil {
                        ActionApprovalCard(chatID: id)
                    }
                    if let error = assistant.error {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(error).font(.callout)
                        }
                        if assistant.microphoneDenied {
                            Button("Open Privacy Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
            }
            .scrollIndicators(.never)
            .frame(height: min(bodyHeight, maxBody))

            HStack(spacing: 16) {
                let speaking = Speaker.shared.isSpeaking
                button(speaking ? "Stop Speaking" : "Speak", speaking ? "stop.fill" : "speaker.wave.2") { assistant.speakLastAnswer() }
                    .disabled(answer == nil && !speaking)
                button("Stop", "stop.circle") {
                    assistant.stopAll()
                    NotchPanelController.shared.collapse()
                }
                Spacer()
                button("Open in Window", "arrow.up.forward.app") {
                    NotchPanelController.shared.collapse()
                    MainWindow.show(id)
                }
                button("New Conversation", "plus.bubble") { assistant.newConversation() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .foregroundStyle(.white)
    }

    private var listeningHint: String {
        switch assistant.phase {
        case .listening: "Listening…"
        case .transcribing: "…"
        default: "Click the face to talk."
        }
    }

    private func button(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(title, systemImage: icon, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.white.opacity(0.7))
            .help(title)
    }
}

/// The tools of the answer, as small capsules.
private struct ToolChips: View {
    let calls: [ToolCall]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(calls) { call in
                    HStack(spacing: 4) {
                        if call.result == nil {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: call.isError ? "exclamationmark.triangle" : "hammer")
                        }
                        Text(call.tool.isEmpty ? call.name : call.tool)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: .capsule)
                }
            }
        }
        .scrollIndicators(.never)
    }
}
