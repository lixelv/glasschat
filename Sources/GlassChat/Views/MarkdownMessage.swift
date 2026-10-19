import MarkdownUI
import SwiftUI

struct MarkdownMessage: View {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(.glassChat)
            .textSelection(.enabled)
    }
}

extension Theme {
    /// System fonts and colours, so answers read like the rest of macOS.
    @MainActor static let glassChat = Theme()
        .text {
            FontFamily(.system())
            FontSize(NSFont.systemFontSize + 1)
            ForegroundColor(.primary)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.92))
            BackgroundColor(Color.secondary.opacity(0.14))
        }
        .strong { FontWeight(.semibold) }
        .link { ForegroundColor(.accentColor) }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 18, bottom: 8)
                .markdownTextStyle { FontWeight(.bold); FontSize(.em(1.5)) }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 16, bottom: 6)
                .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.3)) }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 14, bottom: 4)
                .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.12)) }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 0, bottom: 10)
        }
        .listItem { configuration in
            configuration.label.markdownMargin(top: .em(0.2))
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tertiary)
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle { ForegroundColor(.secondary) }
                    .padding(.leading, 12)
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 0, bottom: 10)
        }
        .codeBlock { configuration in
            CodeBlock(code: configuration.content, language: configuration.language)
                .markdownMargin(top: 4, bottom: 12)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: .secondary.opacity(0.3)))
                .markdownTableBackgroundStyle(.alternatingRows(Color.clear, Color.secondary.opacity(0.06)))
                .markdownMargin(top: 0, bottom: 12)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 { FontWeight(.semibold) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
        }
        .thematicBreak {
            Divider().markdownMargin(top: 12, bottom: 12)
        }
}
