import SwiftUI

struct Composer: View {
    @Binding var text: String
    let isStreaming: Bool
    let send: () -> Void
    let stop: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom, spacing: 10) {
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
                        if !isStreaming { send() }
                        return .handled
                    }

                Button(action: isStreaming ? stop : send) {
                    Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(!isStreaming && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(isStreaming ? "Stop" : "Send")
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
        .onAppear { focused = true }
    }
}
