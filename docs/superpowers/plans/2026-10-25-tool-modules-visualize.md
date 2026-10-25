# Язык Whisper, экономия токенов, модули инструментов, visualize — план

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Whisper не путает язык, запросы дешевле, встроенные инструменты разбиты на модули с двумя поисками, модель рисует визуализации HTML+библиотеками.

**Architecture:** Чистые функции (`WhisperLanguage`, `PromptCache`, `AppModule`, `ToolCatalog`, `VisualPage`, `VisualLibraries.Manifest`) с self-test; `MCPManager.allFunctions` проставляет модуль как группу; `ChatController` различает два поиска; `VisualizationView` — песочница `WKWebView` со схемой `glasschat-viz`.

**Tech Stack:** Swift 6.2, SwiftUI, WebKit (`WKWebView`, `WKContentRuleListStore`, `WKURLSchemeHandler`), WhisperKit `DecodingOptions`, jsDelivr.

**Spec:** `docs/superpowers/specs/2026-10-25-tool-modules-visualize-design.md`

## Global Constraints

- Сборка с `--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`, без макросов с плагинами (`#Preview`, `@Entry`).
- Проверка — `scripts/selftest.sh` (все проходят), затем `scripts/bundle.sh`.
- Ключ модуля в `disabledTools`: `"__app__.<module>"`; старый `"__app__"` → все модули, кроме `necessary`.
- Префикс встроенных: `glasschat__`; скрытый инструмент — имя после `__` начинается с `_`.
- Высота визуализации: ≤ 640 в чате, ≤ 260 в ноче; скрытый рендер — до 3 с; загрузка библиотеки ≤ 10 МБ.
- Текст UI английский; коммит после каждой задачи с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Пользователь раньше выключил весь App (`"__app__"`)** — после обновления все модули, кроме `necessary`, выключены; `app_say` и поиски остаются → Task 3 (миграция в self-test).
2. **Модель вызывает скрытый инструмент без поиска** — «Unknown tool», ответ не падает; `_app_alert` из записки о команде работает → Task 4.
3. **Страница визуализации пытается сходить в сеть или перейти по ссылке** — блокируется, приложение не открывает браузер → Task 6.
4. **Невалидный HTML/JS или бесконечный цикл** — инструмент возвращает ошибки или «Shown.» через 3 с, UI не зависает → Task 6.
5. **Не-Anthropic модель** — запрос без `cache_control`, как раньше → Task 2 (self-test).

---

### Task 1: Язык для Whisper
**Files:** Create `Services/Voice/WhisperLanguage.swift`; Modify `Services/Voice/Transcriber.swift`, `Debug/SelfTests+Language.swift`.
**Produces:** `enum WhisperLanguage { static func hint(appleText: String?, appleLanguage: String?) -> String? }`; `RecognitionLane.Score.language`; `AppleTranscription.language`.
- [ ] Проверки: `("А что ты умеешь", "ru")` → `"ru"`; `("", "ru")` → nil; `(nil, "ru")` → nil; `("Hello", nil)` → nil; `("Hola", "es-ES")` → `"es"`.
- [ ] RED → реализовать; `FinalTranscription` получает `(Recording, String?)`, с подсказкой `DecodingOptions(language:usePrefillPrompt: true, detectLanguage: false)`.
- [ ] GREEN; commit.

### Task 2: Кэш промпта и учёт кэша
**Files:** Create `Services/PromptCache.swift`, `Debug/SelfTests+Tokens.swift`; Modify `Services/OpenAIClient.swift`, `Services/ChatController.swift`, `Debug/SelfTests.swift`.
**Produces:** `enum PromptCache { static func applies(to model: String) -> Bool; static func mark(_ messages: [JSONValue], model: String) -> [JSONValue] }`; `StreamEvent.usage(input:output:cached:)`.
- [ ] Проверки: `applies("anthropic/claude-haiku-5.5")`, `applies("claude-x")` → true, `applies("openai/gpt-5")` → false; для anthropic: system и последний user получают part с `cache_control`, tool-сообщение и средние — без изменений; для openai — массив равен исходному; part-контент (вложения) последнего сообщения: метка на последнем text-part.
- [ ] RED → реализовать; парсинг `usage.prompt_tokens_details.cached_tokens`; лог `chatLog` `usage in out cached`.
- [ ] GREEN; commit.

### Task 3: Модули встроенных инструментов
**Files:** Create `Services/AppModule.swift`, `Debug/SelfTests+Modules.swift`; Modify `Services/AppTools.swift` (имена `_app_notify`, `_app_alert`, короче `app_ask_user`), `Services/MCP/MCPManager.swift` (группы `"__app__.<module>"`, `search_all_tools`), `Services/AppSettings.swift` (миграция, `onDemandServers`), `Services/ToolSearch.swift`, `Debug/SelfTests+Hidden.swift`, `Debug/SelfTests.swift`.
**Produces:** `enum AppModule: String, CaseIterable { case necessary, files, user, chats, models, mcp, visualize; var key: String; var title: String; var summary: String; static func of(_ functionName: String) -> AppModule? }`; `AppSettings.migratedDisabled(_ saved: Set<String>) -> Set<String>`; `MCPManager.searchAllName`.
- [ ] Проверки: у каждого `AppTool`, `RegistryTool`, двух поисков — модуль; `necessary` = {search_tools, search_all_tools, app_say}; `migratedDisabled(["__app__", "srv"])` = все ключи модулей кроме necessary + "srv"; `functions(disabled: все модули)` содержит три necessary-инструмента; `_app_notify`/`_app_alert` скрыты; JSON `app_ask_user` ≤ 600 байт.
- [ ] RED → реализовать; группа `necessary` = nil (не выключается).
- [ ] GREEN; commit.

### Task 4: Два поиска и серверы по требованию
**Files:** Create `Services/ToolCatalog.swift`; Modify `Services/ChatController.swift` (`search_all_tools`, `_app_alert` в найденных при записке), `Services/MCP/MCPManager.swift` (`functions` учитывает `onDemand`), `Debug/SelfTests+Modules.swift`.
**Produces:** `enum ToolCatalog { enum Scope { case hidden, all }; static func candidates(_ all: [String: MCPManager.Function], scope: Scope, disabled: Set<String>, onDemand: Set<String>) -> [String: String]; static func isHidden(_ name: String, group: String?, onDemand: Set<String>) -> Bool }`.
- [ ] Проверки на фикстуре (видимый, скрытый, скрытый в выключенном модуле, инструмент сервера по требованию, поиск): `.hidden` → скрытый + по требованию, без выключенного и без видимых; `.all` → все, кроме поисков; `functions` не предлагает инструменты сервера по требованию.
- [ ] RED → реализовать; описания поисков по спецификации; «нет совпадений» — список только кандидатов.
- [ ] GREEN; commit.

### Task 5: Поповер App и «On demand» в настройках
**Files:** Create `Views/AppToolsSheet.swift`; Modify `Views/Composer.swift`, `Views/MCPSettings.swift`.
- [ ] Строка «App» с «N of M modules on» и кнопкой-chevron → sheet со списком модулей (название, описание, число инструментов, тумблер); `necessary` не показан. В Settings → MCP у сервера — Toggle «On demand».
- [ ] selftest (без регрессий), `bundle.sh`; вручную — Task 8. Commit.

### Task 6: Страница и песочница visualize
**Files:** Create `Services/Visualize/VisualPage.swift`, `Services/Visualize/VisualSandbox.swift` (конфигурация, правила, схема, скрытый рендер с отчётом), `Views/VisualizationView.swift`, `Resources/Visualize/glass.css`, `Debug/SelfTests+Visualize.swift`; Modify `Debug/SelfTests.swift`.
**Produces:** `enum VisualPage { static func html(body: String, libraries: [VisualLibraries.Entry]) -> String }`; `struct VisualizationView: View { init(html: String, libraries: [String], height: Double?, maxHeight: CGFloat) }`; `VisualSandbox.check(html:libraries:) async -> [String]` (ошибки, до 3 с).
- [ ] Проверки: страница содержит `<meta charset="utf-8">`, `glasschat-viz://style/glass.css`, `<script src="glasschat-viz://lib/chart.js/chart.umd.min.js">` для выбранной, тело, отчёт высоты (`webkit.messageHandlers.height`), отчёт ошибок; без библиотек — без `lib/`.
- [ ] RED → реализовать: non-persistent store, правило блокировки `^(https?|file):`, навигация только первая, схема отдаёт `style/` из бандла и `lib/<name>/<file>` только из папки библиотеки (без `..`).
- [ ] GREEN; commit.

### Task 7: Библиотеки, инструменты visualize, показ, директивы
**Files:** Create `Services/Visualize/VisualLibraries.swift`, `Resources/Visualize/libs/chart.js/chart.umd.min.js`, `Resources/Visualize/libs/mermaid/mermaid.min.js`; Modify `Services/AppTools.swift` (`app_visualize`, `_app_install_library`, `_app_remove_library`, описание из манифеста), `Services/AppModule.swift`, `Views/MessageRow.swift`, `Views/Notch/AssistantNotchContent.swift`, `Services/AssistantPrompt.swift`, `Package.swift` (ресурсы), `Debug/SelfTests+Visualize.swift`.
**Produces:** `VisualLibraries.Entry { name, version, files, global, purpose, bundled }`; `VisualLibraries.Manifest` (Codable, `removing(_:)`, `adding(_:)`); `VisualLibraries.downloadURL(package:version:file:) -> URL`.
- [ ] Проверки: манифест по умолчанию — chart.js, mermaid, katex; `removing("mermaid")` убирает, повторный `adding` возвращает; кодирование туда-обратно; URL `https://cdn.jsdelivr.net/npm/d3@7.9.0/dist/d3.min.js`; описание `app_visualize` перечисляет имена и `global`; старый промпт ассистента → `previous`.
- [ ] RED → реализовать; Chart.js и Mermaid скачать в `Resources/Visualize/libs` (версии записать в манифест); установка через `ActionGate`; ограничение 10 МБ.
- [ ] GREEN; commit.

### Task 8: Проверка
- [ ] `scripts/selftest.sh`; ревью ветки (code-reviewer, самая сильная модель).
- [ ] Вживую: короткая русская фраза; `cached` > 0; модули в поповере; поиск скрытого; график и схема в чате и ноче; ошибка JS возвращается; сеть заблокирована; установка/удаление библиотеки.
