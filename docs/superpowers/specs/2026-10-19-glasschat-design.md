# GlassChat — design

Date: 2026-10-19. Status: approved in chat.

## Goal

A native macOS app (macOS 26+, built on macOS 27) that is a chat client for any
OpenAI-compatible API. It must feel like an Apple app: system Liquid Glass
materials, system fonts (SF Pro / SF Mono), standard macOS controls and shortcuts.

Success: the user opens the app, enters URL + token + model once, chats with
streamed answers rendered as markdown, switches the model from the chat window,
and finds every chat in the sidebar after a restart.

Out of scope for v1: attachments, tools/function calling, multiple accounts,
iCloud sync, tests (the user asked for speed: verification is by running the app).

## User-facing behaviour

### First launch / Settings
- No token stored -> an onboarding sheet over the main window (glass card):
  Base URL (default `https://api.openai.com/v1`), API token (secure field), model.
- "Check connection" calls `GET {base}/models`; on success the model field becomes
  a picker of the returned ids (manual entry stays possible); errors are shown inline.
- "Continue" saves and closes. The same fields plus the **global system prompt**
  live in the Settings window (⌘,), a native `Settings` scene with a `Form`.

### Main window
- `NavigationSplitView`: sidebar + detail. The toolbar and sidebar use the
  system Liquid Glass look of macOS 26 (no custom backgrounds over them).
- **Sidebar**: chats sorted by last update, grouped Today / Yesterday / Previous
  7 days / Older; `.searchable` filters by title; "New chat" button (⌘N);
  context menu Rename / Delete; Delete key deletes the selected chat.
- **Toolbar of the chat**: model picker — a glass capsule `Menu` listing models
  from `/models` (cached, refreshed on open) plus "Other…" for manual id; a
  button that opens the chat's system prompt popover (empty = global prompt).
- **Messages**: user messages in a glass bubble aligned right (`.glassEffect`
  with a tint); assistant messages as plain text on the window background,
  rendered as markdown (headings, lists, tables, links, inline code) with code
  blocks in SF Mono, syntax highlighted, with a language label and a Copy
  button; every assistant message has a hover Copy button. Text is selectable.
  The list auto-scrolls to the bottom while streaming unless the user scrolled up.
- **Composer**: a floating glass capsule at the bottom
  (`.glassEffect(.regular.interactive())`), multi-line `TextField(axis: .vertical)`
  growing up to ~8 lines; Enter sends, Shift+Enter inserts a newline; the send
  button turns into Stop while a response streams. Empty chat shows a centered
  greeting with the current model name.
- Chat title = first ~6 words of the first user message (set once).

### Errors
- Network / HTTP errors (status + server `error.message` if present) appear as a
  glass banner above the composer with Retry (resends the last user message).
- On Stop or a broken stream the partial answer is kept and saved.
- 401 -> banner suggests opening Settings.

## Architecture

SwiftPM executable target `GlassChat` (Swift 6, macOS 26), no Xcode project.

```
Package.swift
Sources/GlassChat/
  App/GlassChatApp.swift        @main, WindowGroup + Settings scenes, modelContainer, commands
  Models/Chat.swift             SwiftData @Model Chat, Message (+ Role enum)
  Services/Keychain.swift       token get/set/delete (Security framework)
  Services/AppSettings.swift    @Observable: baseURL, defaultModel, systemPrompt (UserDefaults), token (Keychain)
  Services/OpenAIClient.swift   listModels(), streamChat() -> AsyncThrowingStream<String, Error>
  Services/ChatController.swift @Observable per window: send/stop/retry, streaming state, error
  Views/RootView.swift          split view, onboarding sheet trigger
  Views/SidebarView.swift
  Views/ChatView.swift          message list + composer + banner
  Views/MessageRow.swift        user bubble / assistant markdown
  Views/CodeBlock.swift         MarkdownUI code block style with highlighting + copy
  Views/Composer.swift
  Views/ModelPicker.swift
  Views/OnboardingView.swift
  Views/SettingsView.swift
Resources/Info.plist, AppIcon.icns
scripts/bundle.sh               build release, assemble GlassChat.app, ad-hoc sign, copy to ~/Applications
```

### Data
- `Chat`: id, title, model (String), systemPrompt (String?, nil = global),
  createdAt, updatedAt, messages (cascade).
- `Message`: id, role (`user` | `assistant`), content, createdAt, `isPartial` (Bool).
- Store: SwiftData default container in Application Support.

### API (OpenAI Chat Completions)
- `GET {base}/models` -> `data[].id`, sorted.
- `POST {base}/chat/completions` with `{model, stream: true, messages}`;
  messages = system prompt (if non-empty) + chat history. Header
  `Authorization: Bearer <token>`. Response read with `URLSession.bytes(for:)`,
  lines `data: {...}` -> `choices[0].delta.content`, ends on `data: [DONE]`.
  Non-2xx: body read and decoded as `{error: {message}}` when possible.
- Base URL is used as given (trailing slash trimmed), so OpenRouter, Ollama,
  LM Studio and Omnixon's OpenAI-compatible endpoint work too.

### Streaming flow
`ChatController.send(text)` inserts the user message and an empty assistant
message (`isPartial = true`), starts a `Task` that appends deltas to the
assistant message on the main actor (throttled UI updates are not needed at
first), sets `isPartial = false` at the end, updates `chat.updatedAt`. Stop
cancels the task; the partial text stays.

### Dependencies
- `gonzalezreal/swift-markdown-ui` 2.4.1 (MarkdownUI) — markdown rendering.
- `appstefan/HighlightSwift` 1.1.0 — code highlighting (highlight.js via JavaScriptCore).

### Build and run
`scripts/bundle.sh`: `swift build -c release`, create
`GlassChat.app/Contents/{MacOS,Resources}`, copy the binary and SwiftPM resource
bundles, write Info.plist (bundle id `dev.lixelv.glasschat`, LSMinimumSystemVersion 26.0,
NSHighResolutionCapable), `codesign --force --sign -`, copy to `~/Applications`.
Verification: launch the app, drive it with computer-use, screenshot each screen.
