# GlassChat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **No TDD (user's decision):** every task is verified by `swift build` and, from Task 4 on, by running the bundled app and looking at it.

**Goal:** A native macOS Liquid Glass chat client for any OpenAI-compatible API.

**Architecture:** SwiftPM executable (SwiftUI + SwiftData), a small `OpenAIClient` streaming Chat Completions over SSE, an `@Observable` `ChatController` per window, views split one per file. `scripts/bundle.sh` turns the binary into `~/Applications/GlassChat.app`.

**Tech Stack:** Swift 6.4, SwiftUI / SwiftData (macOS 26 SDK APIs: `glassEffect`, `GlassEffectContainer`), MarkdownUI 2.4.1, HighlightSwift 1.1.0, Command Line Tools only (no Xcode).

**Spec:** `docs/superpowers/specs/2026-10-19-glasschat-design.md`

## Global Constraints

- Platform `.macOS(.v26)`, swift-tools-version 6.2, Swift 6 language mode.
- Bundle id `dev.lixelv.glasschat`, app name `GlassChat`, LSMinimumSystemVersion `26.0`.
- Fonts: system only (`.font(.body)`, `.title3`, `.system(.body, design: .monospaced)` for code). No custom fonts, no hard-coded font sizes except code (13 pt via `.callout` monospaced is fine).
- Glass: system materials only (`.glassEffect`, `.buttonStyle(.glass)` / `.glassProminent`); never paint backgrounds behind sidebar/toolbar.
- Token only in Keychain (service `dev.lixelv.glasschat`, account `api-token`); base URL, default model, system prompt in `UserDefaults` (keys `baseURL`, `defaultModel`, `systemPrompt`).
- Default base URL `https://api.openai.com/v1`; trailing `/` trimmed.
- Commits: one per task, English message, no attribution trailer.

## Review Focus

- Base URL entered with a trailing slash or without `/v1` -> requests go exactly to `{trimmed}/models` and `{trimmed}/chat/completions`; a 404 error message shows the full URL so the user sees the mistake.
- Server that does not implement `/models` (some proxies) -> picker falls back to manual entry, no crash, onboarding can still continue.
- SSE lines with `data: ` chunks that have `delta` without `content` (role-only first chunk, tool deltas) or keep-alive comments `: ping` -> ignored.
- Switching chat in the sidebar while a response streams -> the stream keeps writing into its own chat's message, not into the newly selected one.
- Deleting a chat that is streaming -> the task is cancelled first, no write into a deleted model object.

---

### Task 1: Package skeleton, models, settings, bundling

**Files:**
- Create: `Package.swift`, `.gitignore` (`.build/`, `build/`, `*.app`)
- Create: `Sources/GlassChat/App/GlassChatApp.swift`
- Create: `Sources/GlassChat/Models/Chat.swift`
- Create: `Sources/GlassChat/Services/Keychain.swift`, `Sources/GlassChat/Services/AppSettings.swift`
- Create: `Resources/Info.plist`, `scripts/bundle.sh`

**Interfaces:**
- Produces:
  - `@Model final class Chat { id: UUID; title: String; model: String; systemPrompt: String?; createdAt: Date; updatedAt: Date; @Relationship(deleteRule: .cascade, inverse: \Message.chat) messages: [Message]; var sortedMessages: [Message] }` (sorted by `createdAt`).
  - `@Model final class Message { id: UUID; roleRaw: String; content: String; createdAt: Date; isPartial: Bool; chat: Chat?; var role: Role }`, `enum Role: String { case user, assistant }`.
  - `enum Keychain { static func token() -> String?; static func setToken(_: String?) }`.
  - `@Observable @MainActor final class AppSettings { static let shared; var baseURL: String; var defaultModel: String; var systemPrompt: String; var token: String; var isConfigured: Bool /* token and model non-empty */; var normalizedBaseURL: URL? }` — setters persist immediately.
  - `GlassChatApp`: `WindowGroup { RootView() }` (placeholder `Text` until Task 4) with `.modelContainer(for: [Chat.self, Message.self])`, `Settings { SettingsView() }` placeholder, `.windowToolbarStyle(.unified)`.
  - `scripts/bundle.sh [--open]`: `swift build -c release`, assemble `build/GlassChat.app` (binary to `Contents/MacOS/GlassChat`, `*.bundle` from `.build/release` to `Contents/Resources`, `Info.plist`), `codesign --force --deep --sign -`, `ditto` to `~/Applications/GlassChat.app`, `open` it with `--open`.
- Since SwiftPM executables have no app activation by default: in `GlassChatApp.init` call `NSApplication.shared.setActivationPolicy(.regular)`.

- [ ] **Step 1:** Write `Package.swift` with both dependencies (`from: "2.4.1"` MarkdownUI product `MarkdownUI`, `from: "1.1.0"` HighlightSwift product `HighlightSwift`), executable target `GlassChat` at `Sources/GlassChat`.
- [ ] **Step 2:** Write models, Keychain (`SecItemCopyMatching` / `SecItemAdd` / `SecItemUpdate` / `SecItemDelete`, generic password), AppSettings, app entry, Info.plist, bundle.sh (`chmod +x`).
- [ ] **Step 3:** Run `swift build` — Expected: `Build complete!`. Run `scripts/bundle.sh --open` — Expected: an empty GlassChat window appears with a Dock icon.
- [ ] **Step 4:** Commit `Add package skeleton, data model, settings and bundling`.

### Task 2: OpenAI client

**Files:**
- Create: `Sources/GlassChat/Services/OpenAIClient.swift`

**Interfaces:**
- Consumes: `AppSettings.normalizedBaseURL`, `AppSettings.token`.
- Produces:
  - `struct ChatTurn: Sendable { let role: String; let content: String }` (role `system|user|assistant`).
  - `struct APIError: LocalizedError { let status: Int?; let message: String; let url: URL? }` — `errorDescription` = `"HTTP \(status): \(message)"` (+ URL on 404).
  - `struct OpenAIClient: Sendable { init(baseURL: URL, token: String); func listModels() async throws -> [String]; func streamChat(model: String, messages: [ChatTurn]) -> AsyncThrowingStream<String, Error> }`.
- `listModels`: GET `models`, decode `{data: [{id}]}`, sorted case-insensitively.
- `streamChat`: POST `chat/completions` body `{model, stream: true, messages}`; `URLSession.shared.bytes(for:)`; non-2xx -> collect body, decode `{error:{message}}` else raw text, throw `APIError`; for each line: skip empty and lines starting with `:`; strip `data: `; `[DONE]` ends; decode `choices[0].delta.content` (optional) and yield non-empty. `onTermination` cancels the inner task. Timeout 600 s.

- [ ] **Step 1:** Implement the file.
- [ ] **Step 2:** `swift build` — Expected: `Build complete!`.
- [ ] **Step 3:** Commit `Add OpenAI-compatible client with SSE streaming`.

### Task 3: Chat controller

**Files:**
- Create: `Sources/GlassChat/Services/ChatController.swift`

**Interfaces:**
- Consumes: `Chat`, `Message`, `OpenAIClient`, `AppSettings`.
- Produces: `@Observable @MainActor final class ChatController { var streamingChatIDs: Set<UUID>; var errors: [UUID: String]; func isStreaming(_ chat: Chat) -> Bool; func send(_ text: String, in chat: Chat, context: ModelContext); func stop(_ chat: Chat); func retry(_ chat: Chat, context: ModelContext); func cancelAll(for chat: Chat) }`, plus `func newChat(context: ModelContext) -> Chat` (model = `AppSettings.defaultModel`).
- State is keyed by chat id so switching chats never redirects a stream (Review Focus 4); tasks stored in `[UUID: Task<Void, Never>]`.
- `send`: trim; ignore empty or already streaming; set title once from the first ~6 words (max 60 chars) if title is `"New Chat"`; insert user message + assistant message `isPartial = true`; history = optional system turn (`chat.systemPrompt ?? settings.systemPrompt`, skipped if blank) + all messages except the empty assistant; append deltas to the assistant message's `content`; on finish/cancel/error set `isPartial = false`, `chat.updatedAt = .now`, save; on error remove the assistant message if empty and store `errors[chat.id]`.
- `retry`: drop a trailing assistant message, take the last user message, delete it, call `send` with its text.
- `cancelAll` is called before deleting a chat (Review Focus 5).

- [ ] **Step 1:** Implement the file.
- [ ] **Step 2:** `swift build` — Expected: `Build complete!`.
- [ ] **Step 3:** Commit `Add chat controller`.

### Task 4: Main window — sidebar, chat view, composer

**Files:**
- Create: `Sources/GlassChat/Views/RootView.swift`, `SidebarView.swift`, `ChatView.swift`, `Composer.swift`, `MessageRow.swift` (plain `Text` for assistant until Task 5), `ErrorBanner.swift`
- Modify: `Sources/GlassChat/App/GlassChatApp.swift` (real RootView, `CommandGroup(replacing: .newItem)` "New Chat" ⌘N via a `FocusedValue` or a `NotificationCenter` post)

**Interfaces:**
- Consumes: Task 1 models/settings, Task 3 `ChatController`.
- Produces: `RootView` owns `@State controller = ChatController()` and `@State selection: Chat.ID?`, injects controller via `.environment`.
- Sidebar: `@Query(sort: \Chat.updatedAt, order: .reverse)`, sections Today / Yesterday / Previous 7 Days / Older (`Calendar.isDateInToday` etc.), `.searchable(text:placement: .sidebar)`, row = title (`.body`) + relative date (`.caption`, `.secondary`), `.contextMenu` Rename (alert with TextField) / Delete, `.onDeleteCommand`. Toolbar button `square.and.pencil` "New Chat".
- ChatView: `ScrollView` + `LazyVStack` of `MessageRow`, `.defaultScrollAnchor(.bottom)`, `ScrollViewReader` scrolls to last id on content change; empty state: `ContentUnavailableView`-like centered greeting "What can I help with?" + model name `.secondary`. `.safeAreaInset(edge: .bottom)` holds `ErrorBanner` (glass, Retry + Settings link for 401) and `Composer`.
- Composer: `GlassEffectContainer` with `HStack { TextField("Message", text:, axis: .vertical).lineLimit(1...8).textFieldStyle(.plain); button }`, `.padding`, `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))`; `.onKeyPress(.return)` sends unless Shift held (return `.ignored` with Shift); button `arrow.up` `.buttonStyle(.glassProminent)` / `stop.fill` while streaming; max width 760, centered.
- MessageRow user: trailing aligned `Text` selectable, padding 12/16, `.glassEffect(.regular.tint(.accentColor.opacity(0.25)), in: .rect(cornerRadius: 18))`, max width 560.
- Detail without selection: create/select a new chat automatically on first launch.

- [ ] **Step 1:** Implement the views.
- [ ] **Step 2:** `scripts/bundle.sh --open` — Expected: sidebar with "New Chat", composer capsule at the bottom; with a real token set via `defaults`/Keychain later (Task 6) messages stream. Screenshot it.
- [ ] **Step 3:** Commit `Add main window: sidebar, chat view and composer`.

### Task 5: Markdown, code blocks, copy

**Files:**
- Create: `Sources/GlassChat/Views/MarkdownMessage.swift`, `Sources/GlassChat/Views/CodeBlock.swift`
- Modify: `Sources/GlassChat/Views/MessageRow.swift`

**Interfaces:**
- Produces: `MarkdownMessage(text: String)` = `Markdown(text).markdownTheme(.glassChat).textSelection(.enabled)`; `extension Theme { static let glassChat }` based on `.basic` with system body font, `.monospaced` inline code with a quaternary fill, headings `.title2/.title3/.headline`, and `.codeBlock { CodeBlock(configuration: $0) }`.
- `CodeBlock`: header bar (language label `.caption` `.secondary`, Copy button `doc.on.doc` -> `NSPasteboard`, shows `checkmark` 1.5 s), body `ScrollView(.horizontal)` with `CodeText(configuration.content)` from HighlightSwift (`.codeTextColors(.theme(.github))`, follows light/dark), `.font(.system(.callout, design: .monospaced))`, rounded 12 rect with `.quaternary.opacity(0.5)` fill.
- Assistant row: `MarkdownMessage` full width (max 760); while `isPartial && content.isEmpty` show a pulsing `ProgressView().controlSize(.small)`; hover shows a Copy-answer button (copies raw markdown).

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** `scripts/bundle.sh --open`, ask for "a table and a Python snippet" — Expected: table rendered, code highlighted, Copy works. Screenshot.
- [ ] **Step 3:** Commit `Render answers as markdown with highlighted code blocks`.

### Task 6: Onboarding, Settings, model picker, chat system prompt

**Files:**
- Create: `Sources/GlassChat/Views/OnboardingView.swift`, `SettingsView.swift`, `ModelPicker.swift`, `ConnectionFields.swift`, `Services/ModelStore.swift`
- Modify: `RootView.swift` (`.sheet(isPresented: !settings.isConfigured)`), `ChatView.swift` (toolbar), `GlassChatApp.swift` (Settings scene)

**Interfaces:**
- Produces: `@Observable @MainActor final class ModelStore { static let shared; var models: [String]; var lastError: String?; func refresh() async }` (uses current settings; keeps old list on error).
- `ConnectionFields` (shared by onboarding and Settings): `Form` `.formStyle(.grouped)` with Base URL `TextField`, Token `SecureField`, Model (Picker of `ModelStore.models` when non-empty + TextField for manual id), "Check Connection" button showing a spinner / `checkmark.circle.fill` green / error text in red `.callout`.
- Onboarding: sheet, 460 wide; app icon symbol `bubble.left.and.text.bubble.right.fill` large, title "Welcome to GlassChat" `.largeTitle.bold()`, subtitle `.secondary`, `ConnectionFields`, "Continue" `.buttonStyle(.glassProminent)` disabled until token+model non-empty; `.interactiveDismissDisabled()`.
- SettingsView: `TabView` with tabs "Connection" (`ConnectionFields`) and "Prompt" (`TextEditor` for global system prompt), frame 520x420.
- ModelPicker (toolbar, `.principal` or primary action): `Menu` with label `Label(chat.model, systemImage: "cpu")` in a capsule; items = models (checkmark on current), `Divider`, "Other…" (alert with TextField), "Refresh". Changing sets `chat.model` and `settings.defaultModel`. `.task { await ModelStore.shared.refresh() }`.
- Chat system prompt: toolbar button `text.bubble` with `.popover` containing `TextEditor` bound to `chat.systemPrompt` (empty string -> nil) and caption "Empty uses the global prompt".

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Reset state (`defaults delete dev.lixelv.glasschat`; delete the Keychain item), `scripts/bundle.sh --open` — Expected: onboarding appears; entering a real URL/token lists models; Continue opens the chat; picker switches models; a chat answers with the chosen model. Screenshots of onboarding, chat, Settings.
- [ ] **Step 3:** Commit `Add onboarding, settings, model picker and per-chat system prompt`.

### Task 7: Polish and app icon

**Files:**
- Create: `scripts/make-icon.swift` (renders a 1024 px icon: glass-like gradient squircle with a white `bubble.left.and.bubble.right.fill` symbol, via AppKit -> `iconutil`), `Resources/AppIcon.icns`
- Modify: `scripts/bundle.sh` (copy icon; `CFBundleIconFile`), `README.md`

- [ ] **Step 1:** Generate the icon, wire it in, write README (build/run, supported servers).
- [ ] **Step 2:** Walk through the Review Focus list by hand in the running app (trailing slash URL, a server without `/models` — e.g. a wrong base URL, switching chats while streaming, deleting a streaming chat). Fix what breaks.
- [ ] **Step 3:** `scripts/bundle.sh --open` final screenshots; commit `Add app icon, README and polish`.
