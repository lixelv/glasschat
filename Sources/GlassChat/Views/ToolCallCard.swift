import SwiftUI

/// One MCP tool call in an answer: folded to its name, unfolded to the arguments and the result.
struct ToolCallCard: View {
    let call: ToolCall
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Group {
                        if call.result == nil {
                            ProgressView().controlSize(.small)
                        } else if call.isError {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        } else {
                            Image(systemName: "hammer.fill").foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 16)
                    Text(call.tool.isEmpty ? call.name : call.tool)
                        .font(.callout.weight(.medium))
                    Text(MCPManager.shared.displayName(ofSlug: call.server))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 10) {
                    section("Arguments", Self.pretty(call.arguments))
                    if let result = call.result { section(call.isError ? "Error" : "Result", Self.pretty(result)) }
                }
                .padding([.horizontal, .bottom], 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
        // While the card folds, its details are cut by its edge instead of spilling over the next card.
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            // Long results are cut at 16 lines; the text stays selectable.
            Text(text.isEmpty ? "—" : text)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(16)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// JSON pretty-printed; anything else as it is.
    static func pretty(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return text }
        return String(decoding: pretty, as: UTF8.self)
    }
}
