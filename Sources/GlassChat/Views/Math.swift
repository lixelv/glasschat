import AppKit
import MarkdownUI
import SwiftUI

/// LaTeX in answers. Formulas are turned into markdown images with a `glasschat-math:` URL before
/// MarkdownUI parses the text; the image providers below render them with KaTeX (`MathRenderer`).
enum MathMarkdown {
    static let scheme = "glasschat-math"

    /// KaTeX draws at 1.21em of this; 1.05 sets the formulas to the size of the body text.
    @MainActor static var inlineFontSize: CGFloat { (NSFont.systemFontSize + 1) / 1.21 * 1.05 }
    /// A display formula ($$) is this much larger than an inline one ($); chosen by the user.
    /// Space above and below a display formula: 1.5 times the 14 pt it had (a paragraph's 10 pt margin + 4 pt padding).
    static let displayGap: CGFloat = 14 * 1.5 - 10
    static let displayScale: CGFloat = 1.21

    /// Rewrites `$$..$$`, `\[..\]` (display) and `$..$`, `\(..\)` (inline) outside code.
    static func prepare(_ markdown: String) -> String {
        guard markdown.contains("$") || markdown.contains("\\(") || markdown.contains("\\[") else { return markdown }
        var out = ""
        var inFence = false
        var proseLines: [Substring] = []

        func flush() {
            guard !proseLines.isEmpty else { return }
            out += convert(proseLines.joined(separator: "\n"))
            proseLines.removeAll()
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if !inFence { flush() }
                inFence.toggle()
                out += line + "\n"
            } else if inFence {
                out += line + "\n"
            } else {
                proseLines.append(line)
            }
        }
        flush()
        if !markdown.hasSuffix("\n"), out.hasSuffix("\n") { out.removeLast() }
        return out
    }

    /// Prose without fences: keeps inline code spans as they are.
    private static func convert(_ text: String) -> String {
        var result = ""
        let chars = Array(text)
        var i = 0
        var displayDepth = 0 // unused guard for readability

        func find(_ token: String, from start: Int) -> Int? {
            let t = Array(token)
            var j = start
            while j + t.count <= chars.count {
                if Array(chars[j..<j + t.count]) == t, j == 0 || chars[j - 1] != "\\" || token.hasPrefix("\\") { return j }
                j += 1
            }
            return nil
        }

        while i < chars.count {
            let c = chars[i]
            // Inline code: copy through.
            if c == "`" {
                var ticks = 0
                while i + ticks < chars.count, chars[i + ticks] == "`" { ticks += 1 }
                let fence = String(repeating: "`", count: ticks)
                if let end = find(fence, from: i + ticks) {
                    result += String(chars[i..<end + ticks])
                    i = end + ticks
                    continue
                }
            }
            // Escaped dollar stays a dollar.
            if c == "\\", i + 1 < chars.count, chars[i + 1] == "$" {
                result += "\\$"
                i += 2
                continue
            }
            if c == "$", i + 1 < chars.count, chars[i + 1] == "$", let end = find("$$", from: i + 2) {
                result += block(String(chars[i + 2..<end]))
                i = end + 2
                continue
            }
            if c == "\\", i + 1 < chars.count, chars[i + 1] == "[", let end = find("\\]", from: i + 2) {
                result += block(String(chars[i + 2..<end]))
                i = end + 2
                continue
            }
            if c == "\\", i + 1 < chars.count, chars[i + 1] == "(", let end = find("\\)", from: i + 2) {
                result += inline(String(chars[i + 2..<end]))
                i = end + 2
                continue
            }
            // $x$ by pandoc's rule: no space after the opening $, none before the closing one,
            // no digit right after it (so "$5 and $10" stays text), on one line.
            if c == "$", i + 1 < chars.count, !chars[i + 1].isWhitespace, chars[i + 1] != "$" {
                var j = i + 1
                var end: Int?
                while j < chars.count, chars[j] != "\n" {
                    if chars[j] == "$", chars[j - 1] != "\\" {
                        if !chars[j - 1].isWhitespace, j + 1 >= chars.count || !chars[j + 1].isNumber { end = j }
                        break
                    }
                    j += 1
                }
                if let end {
                    result += inline(String(chars[i + 1..<end]))
                    i = end + 1
                    continue
                }
            }
            result.append(c)
            i += 1
        }
        _ = displayDepth
        return result
    }

    private static func url(_ tex: String, display: Bool) -> String {
        let data = Data(tex.trimmingCharacters(in: .whitespacesAndNewlines).utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(scheme):\(display ? "display" : "inline")/\(data)"
    }

    private static func block(_ tex: String) -> String {
        "\n\n![formula](\(url(tex, display: true)))\n\n"
    }

    private static func inline(_ tex: String) -> String {
        // A leading zero-width space keeps an image that starts a paragraph inline, not a block.
        "\u{200B}![formula](\(url(tex, display: false)))"
    }

    /// The LaTeX and the mode a `glasschat-math:` URL carries.
    static func decode(_ url: URL?) -> (tex: String, display: Bool)? {
        guard let url, url.scheme == scheme else { return nil }
        let parts = url.absoluteString.dropFirst(scheme.count + 1).split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let tex = String(data: data, encoding: .utf8) else { return nil }
        return (tex, parts[0] == "display")
    }

    @MainActor static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// Inline formulas inside a line of text.
struct MathInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        guard let (tex, _) = MathMarkdown.decode(url) else { return try await DefaultInlineImageProvider.default.image(with: url, label: label) }
        if let formula = await MathRenderer.shared.image(tex: tex, display: false, fontSize: MathMarkdown.inlineFontSize,
                                                        dark: await MathMarkdown.isDark) {
            // The formula's baseline on the text's: text runs through its middle, not under it.
            InlineImageMetrics.shared.setBaselineOffset(-formula.depth, for: url.absoluteString)
            return Image(nsImage: formula.image)
        }
        throw URLError(.cannotDecodeContentData)
    }
}

/// Display formulas on a line of their own; the source is shown when it cannot be parsed.
struct MathImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        if let (tex, _) = MathMarkdown.decode(url) {
            DisplayFormula(tex: tex)
        } else {
            DefaultImageProvider.default.makeImage(url: url)
        }
    }
}

private struct DisplayFormula: View {
    let tex: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                // Centred; a formula wider than the column is scaled down to fit.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: image.size.width)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MathMarkdown.displayGap)
            } else if failed {
                Text(tex)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Color.clear.frame(height: 28)
            }
        }
        .task(id: "\(colorScheme)|\(tex)") {
            let rendered = await MathRenderer.shared.image(tex: tex, display: true, fontSize: MathMarkdown.inlineFontSize * MathMarkdown.displayScale,
                                                           dark: colorScheme == .dark)
            image = rendered?.image
            failed = rendered == nil
        }
    }
}
