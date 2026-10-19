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
                    ToolDuration(call: call)
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
            ClippedOutput(text: text.isEmpty ? "—" : text)
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

/// How long a call took; while it runs, the time so far.
struct ToolDuration: View {
    let call: ToolCall

    var body: some View {
        if let start = call.startedAt {
            if let end = call.finishedAt {
                Text(Self.format(end.timeIntervalSince(start)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if call.result == nil {
                TimelineView(.periodic(from: start, by: 0.1)) { context in
                    Text(Self.format(context.date.timeIntervalSince(start)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        seconds < 60 ? String(format: "%.1f s", max(seconds, 0)) : String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

/// The tool calls of a step, folded by default into one line ("Used 3 tools"); unfolded, a card per call.
struct ToolCallsGroup: View {
    let calls: [ToolCall]
    @State private var open = false

    private var running: Int { calls.filter { $0.result == nil }.count }
    private var failed: Int { calls.filter(\.isError).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    if running > 0 {
                        ProgressView().controlSize(.mini)
                        Text(running == calls.count ? "Running \(calls.count) \(calls.count == 1 ? "tool" : "tools")…"
                                                    : "Running \(running) of \(calls.count) tools…")
                    } else {
                        Image(systemName: failed > 0 ? "exclamationmark.triangle" : "hammer")
                            .foregroundStyle(failed > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        Text("Used \(calls.count) \(calls.count == 1 ? "tool" : "tools")" + (failed > 0 ? ", \(failed) failed" : ""))
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(calls) { ToolCallCard(call: $0) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}

/// A tool's arguments or result: the first lines, and "Show more" for the whole text.
private struct ClippedOutput: View {
    let text: String
    @State private var expanded = false

    static let lines = 12
    static let characters = 1_200

    private var preview: String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > Self.lines || text.count > Self.characters else { return nil }
        var cut = lines.prefix(Self.lines).joined(separator: "\n")
        if cut.count > Self.characters { cut = String(cut.prefix(Self.characters)) }
        return cut + "…"
    }

    var body: some View {
        let preview = preview
        VStack(alignment: .leading, spacing: 6) {
            Text(expanded || preview == nil ? text : preview!)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if preview != nil {
                Button(expanded ? "Show less" : "Show more (\(text.split(separator: "\n", omittingEmptySubsequences: false).count) lines)") {
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }
}
