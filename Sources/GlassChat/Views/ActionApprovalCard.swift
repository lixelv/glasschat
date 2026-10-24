import SwiftUI

/// A file or terminal action waiting for the user: red when the decision model did not call it safe.
struct ActionApprovalCard: View {
    let chatID: Chat.ID
    private var center = ApprovalCenter.shared

    init(chatID: Chat.ID) {
        self.chatID = chatID
    }

    var body: some View {
        if let pending = center.pending[chatID] {
            let action = pending.action
            let tint: Color = action.dangerous ? .red : .accentColor
            VStack(alignment: .leading, spacing: 8) {
                Label(action.dangerous ? "This may be dangerous" : "Allow this action?",
                      systemImage: action.dangerous ? "exclamationmark.octagon.fill" : "hand.raised.fill")
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(action.summary)
                    .font(.callout)
                Text(action.detail.isEmpty ? "—" : action.detail)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(12)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                HStack {
                    Button("Deny") { center.answer(.deny, in: chatID) }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Allow in This Chat") { center.answer(.allowInChat, in: chatID) }
                    Button("Allow") { center.answer(.allow, in: chatID) }
                        .buttonStyle(.glassProminent)
                        .tint(tint)
                }
            }
            .padding(12)
            .background(tint.opacity(action.dangerous ? 0.12 : 0.06), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.5)))
            .frame(maxWidth: 560, alignment: .leading)
        }
    }
}
