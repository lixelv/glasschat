# Локальный голос, скрытые инструменты и инструменты файлов/терминала — план

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Supertonic 3 и WhisperKit вместо голосов/распознавания провайдера, инструменты с `_` скрыты от модели, новые `app_read/app_write/app_edit/app_bash` с подтверждением через Jev или пользователя, промпт «отвечай голосом на каждый запрос».

**Architecture:** Логика инструментов — чистые функции (`FileTools`, `ShellRunner`, `HiddenTools`, `ApprovalPolicy`), покрытые self-test; ожидание решения пользователя — `ApprovalCenter` по образцу `QuestionCenter`. Голосовые модели — `VoiceModels` (загрузка и держатель WhisperKit/Supertonic); `Speaker` и `Transcription` переключаются на них с запасом на Apple.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, WhisperKit 0.18.0, supertonic.swift (rev e26051d3, ONNX Runtime 1.24.2), Foundation `Process`.

**Spec:** `docs/superpowers/specs/2026-10-25-local-voice-and-file-tools-design.md`

## Global Constraints

- Сборка: `--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`; без `#Preview`/`@Entry`/макросов с плагинами.
- Зависимости: WhisperKit `exact: "0.18.0"`, supertonic.swift `revision: "e26051d3…"` (полный хеш из Package.resolved пробы), swift-collections `"1.1.0"..<"1.3.0"`; `Package.resolved` коммитится.
- Модели — в `~/Library/Application Support/GlassChat/models/`; Whisper-вариант `large-v3-v20240930_turbo`, не настраивается.
- Новые инструменты: имена `app_read`, `app_write`, `app_edit`, `app_bash`; скрытые — префикс `_` (список в спецификации §3).
- Текст интерфейса — английский; коммит после каждой задачи с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Проверка логики: `scripts/selftest.sh` → `SELF-TEST: all N passed`.

## Review Focus

1. **Путь с пробелами, `~` и относительный** в read/write/edit/bash — должен работать; относительный — от рабочей папки чата → Task 2 (`resolvePath`), Task 3.
2. **Команда, которая висит или печатает гигабайты** (`yes`, `sleep 999`) — тайм-аут убивает процесс, вывод обрезан, приложение не зависает → Task 3.
3. **Отмена ответа во время bash или карточки подтверждения** — процесс убит / карточка снята, ответ не висит → Task 3, Task 4.
4. **Нет интернета или ошибка загрузки моделей** — приложение работает на Apple/голосе macOS, в настройках ошибка и «Download again» → Task 5.
5. **Старые чаты с вызовами старых имён инструментов** (`glasschat__app_list_chats`) — история показывается, повторный вызов модели получает «Unknown tool» → Task 1 (не ломать декодирование).

---

### Task 1: Зависимости и скрытые инструменты

**Files:** Modify `Package.swift`, `Services/MCP/MCPManager.swift` (RegistryTool raw values, `functions`), `Services/AppTools.swift` (raw values); Create `Services/HiddenTools.swift`, `Debug/SelfTests+Hidden.swift`.

**Interfaces — Produces:** `enum HiddenTools { static func isHidden(_ functionName: String) -> Bool }` — имя инструмента после первого `__` начинается с `_`.

- [ ] Проверки (`hidden()`): `isHidden("glasschat___app_list_chats")`, `isHidden("github___private")`, `!isHidden("glasschat__app_say")`, `!isHidden("_weird")` (нет `__`); `functions` не содержит скрытой функции без `found`, содержит с `found`.
- [ ] RED → реализовать: переименовать raw values по списку спецификации; в `MCPManager.functions` дополнительно отбрасывать `HiddenTools.isHidden(name) && !found.contains(name)`; добавить зависимости в `Package.swift` (продукты в цель `GlassChat`), `swift package resolve`.
- [ ] GREEN, `scripts/bundle.sh` собирается; commit.

### Task 2: Файловые инструменты

**Files:** Create `Services/FileTools.swift`, `Debug/SelfTests+FileTools.swift`; Modify `Services/AppTools.swift`.

**Interfaces — Produces:** `enum FileTools { static func resolvePath(_ path: String, cwd: URL) -> URL; static func read(_ url: URL, offset: Int?, limit: Int?) throws -> String; static func write(_ url: URL, content: String) throws -> String; static func edit(_ url: URL, old: String, new: String, replaceAll: Bool) throws -> String }`.

- [ ] Проверки во временной папке: нумерация `"     1\tone\n     2\ttwo"`; `offset: 2, limit: 1` → только строка 2; строка 2500 символов → обрезана до 2000 + `…`; файл с `\0` → ошибка «binary»; папка → `"a.txt\nsub/"` (сортировка, `/` у папок); `write` создаёт вложенные папки; `edit` одна замена; нет совпадения → ошибка; 2 совпадения без `replaceAll` → ошибка с «2»; `replaceAll` → «Replaced 2»; `resolvePath("~/x")`, `"rel/y"` от cwd, путь с пробелами.
- [ ] RED → реализовать; `AppTool.read/.write/.edit` (raw `app_read/app_write/app_edit`), описания и схемы как в спецификации §4; `perform` вызывает `FileTools` с `cwd` = `ShellRunner.workingDirectory(for: chatID)` (Task 3; до него — домашняя папка).
- [ ] GREEN; commit.

### Task 3: `app_bash`

**Files:** Create `Services/ShellRunner.swift`, `Debug/SelfTests+Shell.swift`; Modify `Services/AppTools.swift`.

**Interfaces — Produces:** `actor ShellRunner { static let shared; func workingDirectory(for chat: Chat.ID) -> URL; func run(_ command: String, in chat: Chat.ID, timeout: TimeInterval) async -> (output: String, exitCode: Int32, timedOut: Bool) }`; `static let maxOutput = 30_000`.

- [ ] Проверки (через `await` в self-test — `SelfTests` получает async-сьют): `echo hi` → «hi», код 0; `exit 3` → код 3; `cd /tmp` затем `pwd` → `/tmp` (папка сохраняется); `sleep 5` с timeout 0.5 → `timedOut` и возврат < 3 с; `yes | head -c 100000` → вывод ≤ 30 000 + пометка об обрезке.
- [ ] RED → реализовать: `/bin/zsh -l -c "<cmd>; __s=$?; printf '\n__GLASSCHAT_PWD__%s' \"$PWD\"; exit $__s"`, `currentDirectoryURL` = папка чата; чтение pipe в фоне; по тайм-ауту SIGTERM, через 2 с SIGKILL; отмена задачи → то же. `AppTool.bash` (`app_bash`, параметры `command`, `timeout`), результат — вывод + `"\nExit code: N"`.
- [ ] GREEN; commit.

### Task 4: Подтверждение действий

**Files:** Create `Services/ActionApproval.swift`, `Views/ActionApprovalCard.swift`, `Debug/SelfTests+Approval.swift`; Modify `Services/ToolSearch.swift` (общий запрос решений), `Services/AppTools.swift`, `Services/AppSettings.swift`, `Views/MessageRow.swift`, `Views/Notch/AssistantNotchContent.swift`, `Services/ChatController.swift` (dismiss при delete).

**Interfaces — Produces:**
- `enum ConfirmMode: String { case auto, always, never }` — `AppSettings.confirmActions` (по умолчанию `.auto`).
- `enum ApprovalPolicy { enum Verdict { case run, ask(dangerous: Bool) }; static func verdict(mode: ConfirmMode, safeProbability: Double?, allowedInChat: Bool) -> Verdict }`.
- `Decisions.choose(state: String, instructions: String, options: [String: String]) async throws -> [String: Double]` (вынести из `ToolSearch.decide`; `ToolSearch` использует его).
- `@Observable @MainActor final class ApprovalCenter { static let shared; private(set) var pending: [Chat.ID: PendingApproval]; func approve(_ action: PendingAction, in chat: Chat.ID) async -> Bool; func answer(_ decision: ApprovalDecision, in chat: Chat.ID); func dismiss(in chat: Chat.ID) }`, `enum ApprovalDecision { case allow, allowInChat, deny }`, `struct PendingAction { tool: AppTool; summary: String; detail: String; dangerous: Bool }`.

- [ ] Проверки `verdict`: never → run; always → ask(false); auto + 0.9 → run; auto + 0.3 → ask(true); auto + nil → ask(true); allowedInChat → run в auto и always.
- [ ] RED → реализовать; в `perform` для write/edit/bash: спросить Jev (`options: ["safe": "…harmless…", "dangerous": "…can destroy data, leak secrets, change the system…"]`, `state` — инструмент, команда/путь, рабочая папка), затем `verdict`; `ask` → `ApprovalCenter.approve`; отказ → ошибка «The user denied this action.». Карточка: красный заголовок при `dangerous`, моноширинная команда/путь, кнопки Allow / Allow in This Chat / Deny; в ленте после шага с этим вызовом и в ноче. Ноч раскрывается при ожидающем подтверждении (как вопрос).
- [ ] GREEN; commit.

### Task 5: Голосовые модели — WhisperKit и Supertonic

**Files:** Create `Services/Voice/VoiceModels.swift`, `Debug/SelfTests+Voice.swift`; Modify `Services/Voice/Transcriber.swift`, `Services/Voice/Speaker.swift`, `Services/AppSettings.swift`, `Models/ModelConnection.swift`, `Services/OpenAIClient.swift`, `GlassChatApp.swift`; Delete `Services/Voice/LocalWhisper.swift`, `Views/RecognitionSettings.swift` части whisper.cpp, `Services/MultipartForm.swift` (+ его self-test), если не используется.

**Interfaces — Produces:**
- `@Observable @MainActor final class VoiceModels { static let shared; enum State: Equatable { case missing, downloading(Double), ready, failed(String) }; private(set) var whisper: State; private(set) var speech: State; func downloadAll() async; func transcriber() async throws -> WhisperKit; func synthesizer() throws -> Supertonic }`.
- `RecognitionMode` = `builtIn`, `whisper`; `static func migrated(_ raw: String?) -> RecognitionMode` (`localWhisper` → `whisper`, прочее → `builtIn`).
- `enum SupertonicLanguage { static func language(for text: String) -> Language }` (неизвестный → `.na`).
- `AppSettings.supertonicVoice: String` (raw `Voice`).

- [ ] Проверки: `migrated("localWhisper") == .whisper`, `migrated("provider") == .builtIn`, `migrated("audioToModel") == .builtIn`, `migrated(nil) == .builtIn`; язык Supertonic: русский текст → `.russian`, английский → `.english`, «1234» → `.na`.
- [ ] RED → реализовать: загрузка в `models/` (`WhisperKit.download(variant: "large-v3-v20240930_turbo", downloadBase:, progressCallback:)`, `ModelAssets.download(to:progress:)`); `Transcription.start` для `.whisper` → `FinalTranscription` с `WhisperKit.transcribe(audioPath:)`, пока модель не `ready` — Apple; `Speaker` — Supertonic (`synthesize` → буфер в `AVAudioPlayerNode`, уровень из сэмплов), запасной `AVSpeechSynthesizer`; убрать `ModelRole.transcription/.speech`, TTS/transcribe из клиента; запуск `downloadAll()` при старте, если что-то `missing`.
- [ ] GREEN; `bundle.sh`; commit.

### Task 6: Промпт, настройки, онбординг

**Files:** Modify `Services/AssistantPrompt.swift`, `Services/AppSettings.swift`, `Views/AssistantSettings.swift`, `Views/RecognitionSettings.swift`, `Views/OnboardingView.swift`, `Debug/SelfTests+Context.swift`, `README.md`.

- [ ] Проверки: пустой сохранённый промпт при загрузке → `AssistantPrompt.standard`; новый `standard` содержит `glasschat__app_say` и `glasschat__search_tools`.
- [ ] RED → реализовать: новый текст по спецификации §1; поле без плейсхолдера, Reset записывает стандарт; настройки: Recognition (Apple / Whisper large-v3-turbo + статус загрузки), Voice (голос Supertonic, статус), Tools → Confirm actions (Auto/Always ask/Never ask + предупреждение), строки моделей — только Default и Decision; онбординг шаг 3 «Voice models» с прогрессом обеих моделей и «Continue»; README.
- [ ] GREEN; `bundle.sh --open`; commit.

### Task 7: Финальная проверка

- [ ] `scripts/selftest.sh`; ревью всей ветки по `requesting-code-review` (самостоятельно, если нет субагента).
- [ ] Запуск: загрузка моделей, голос Supertonic (ru/en), Whisper, `app_bash ls` с карточкой/без, скрытые инструменты не в запросе (лог), `search_tools` находит `_app_list_chats`.
