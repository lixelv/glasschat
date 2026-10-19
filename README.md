# GlassChat

A native macOS chat client for any OpenAI-compatible API (OpenAI, OpenRouter, Ollama, LM Studio, …),
built with SwiftUI and Liquid Glass. Chats live in the sidebar, the model is switched from the chat
window, answers stream in and are rendered as markdown with highlighted code and LaTeX
(`$..$`, `\(..\)`, `$$..$$`, `\[..\]`, drawn by a bundled KaTeX 0.16.11 in a hidden web view, offline).

Requires macOS 26 or later.

## Build and install

Only the Command Line Tools are needed (no Xcode):

```bash
scripts/bundle.sh --open
```

It builds a release binary, assembles `GlassChat.app`, signs it ad hoc and installs it in `~/Applications`.

Notes:
- The app builds against the macOS 26.5 SDK: the macOS 27 SDK and SwiftData's `@Model` need macro
  plugins that ship only with Xcode. Chats are therefore kept as JSON in
  `~/Library/Application Support/GlassChat/chats.json`.
- `Vendor/HighlightSwift` is HighlightSwift 1.1.0 with `@Entry` and `#Preview` removed for the same reason.
- `Vendor/swift-markdown-ui` is MarkdownUI 2.4.1 with two patches: an inline image can be moved off the baseline
  (`InlineImageMetrics`, so a formula's baseline meets the text's) and one failing inline image no longer drops the others.
- `scripts/make-icon.swift <dir>.iconset` renders the icon; `iconutil -c icns` turns it into `Resources/AppIcon.icns`.

## Files and MCP

- **Files**: the paperclip in the message field, ⌘V, or drop files on the window (the field turns into a drop zone).
  Images go as `image_url`, audio as `input_audio`, text and code inline, PDFs and anything else as `file`
  (base64); a model that cannot read a type says so. Copies are kept in `~/Library/Application Support/GlassChat/files`.
- **MCP**: Settings → MCP. Local servers (stdio) run through your login shell, remote ones use Streamable HTTP
  with optional headers. Their tools are offered to the model as functions (`server__tool`); calls run without asking,
  in parallel, up to 20 rounds per answer, and show as cards in the chat. The hammer button in a chat switches servers
  off for that chat. The list is kept in `mcp.json` beside the chats.

## Settings

On first launch the app asks for the base URL (default `https://api.openai.com/v1`), the API token
(stored in the Keychain) and the model. All of it, plus a global system prompt, is in Settings (⌘,).
Each chat can have its own system prompt (toolbar button).
