# GlassChat — язык Whisper, экономия токенов, модули инструментов, visualize

Дата: 2026-10-25. Статус: одобрено в чате («пиши спецификацию, планируй и начинай, я всё поддерживаю»).
Ветка `feature/notch-assistant`. Формат visualize выбран пользователем: HTML+CSS+JS + локальные библиотеки.

## Цель

1. Whisper не путает язык коротких фраз.
2. Каждый запрос дешевле и быстрее: кэш промпта, меньше инструментов в каждом запросе.
3. Встроенные инструменты разбиты на модули, которые пользователь включает по одному; редкие скрыты (`_`).
   `search_tools` ищет только скрытые, `search_all_tools` — всё.
4. Новый инструмент `app_visualize`: HTML/CSS/JS с локальными библиотеками в чате и в ноче; модель знает
   библиотеки и может ставить/удалять их; директивы, когда визуализировать.

## 1. Язык Whisper

- `RecognitionLane.Score` получает `language: String?` — код языка локали своей полосы («ru», «en»).
- `AppleTranscription.finish` запоминает язык победившей полосы: `private(set) var language: String?`.
- Чистая функция `WhisperLanguage.hint(appleText: String?, appleLanguage: String?) -> String?`:
  код языка (2–3 строчные буквы), если Apple услышал слова (`SpeechText.isWords`) и язык известен; иначе `nil`.
- `FinalTranscription` передаёт подсказку в Whisper: с ней —
  `DecodingOptions(language: hint, usePrefillPrompt: true, detectLanguage: false)`; без неё — как сейчас
  (`usePrefillPrompt: false, detectLanguage: true`).

## 2. Экономия токенов

### Кэш промпта (Anthropic через OpenRouter)
- Чистая функция `PromptCache.mark(_ messages: [JSONValue], model: String) -> [JSONValue]`: для моделей
  `anthropic/…` (или с `claude` в id) первое `system`-сообщение и последнее сообщение со строковым `content`
  (не `tool`) получают `content: [{"type": "text", "text": …, "cache_control": {"type": "ephemeral"}}]`.
  Для остальных моделей сообщения не меняются. Порядок кэша Anthropic: tools → system → messages, поэтому первая
  метка кэширует инструменты и промпт, вторая — историю. Минимум кэша у Haiku 5.5 — 512 токенов.
- `OpenAIClient.streamChat` применяет `PromptCache.mark`. `StreamEvent.usage` получает `cached: Int`
  (`prompt_tokens_details.cached_tokens`), он пишется в лог `chat` (`usage in=… cached=… out=…`).

### Меньше инструментов в запросе
- Скрытые (`_`) встроенные инструменты — раздел 3.
- Серверы MCP «по требованию»: `AppSettings.onDemandServers: Set<String>` (id серверов). Инструменты такого сервера
  считаются скрытыми: не уходят в запрос, находятся через `search_tools`. Переключатель «On demand» — в строке
  сервера в Settings → MCP.
- Описание `app_ask_user` сокращается (≤ 600 байт JSON вместе с параметрами).
- Второй запрос после `app_say` остаётся (иначе голос начинается только после всего текста).

## 3. Модули встроенных инструментов и два поиска

### Модули
`AppModule` (enum, `rawValue` — ключ), у каждого встроенного инструмента ровно один модуль:

| Модуль | Название в UI | Инструменты |
|---|---|---|
| `necessary` | — (не показывается, всегда включён) | `search_tools`, `search_all_tools`, `app_say`, `app_ask_user` |
| `files` | Files & Terminal | `app_read`, `app_write`, `app_edit`, `app_bash` |
| `user` | Notifications & Alerts | `_app_notify`, `_app_alert` |
| `chats` | Chats | `_app_list_chats`, `_app_create_chat`, `_app_switch_chat`, `_app_rename_chat`, `_app_delete_chat` |
| `models` | Models | `_app_list_models`, `_app_set_model` |
| `mcp` | MCP Servers | `_app_list_mcp`, `_app_enable_mcp`, `_app_disable_mcp`, `_mcp_registry_list/get/add/update/delete` |
| `visualize` | Visualize | `app_visualize`, `_app_install_library`, `_app_remove_library` |

- Скрытые (`_`, редкие): уведомление, окно-алерт, всё про чаты, модели, MCP-реестр, установка/удаление библиотек.
  Видимые: `app_say`, `app_ask_user`, файлы и терминал, `app_visualize`, два поиска.
- Ключ выключения модуля в `AppSettings.disabledTools`: `"__app__.<module>"`. Старый ключ `"__app__"`
  (весь App выключен) при чтении настроек заменяется ключами всех модулей, кроме `necessary`.
- `necessary` нельзя выключить; его нет в UI.

### UI
- Поповер «Tools» в поле ввода: строка «App» без тумблера; справа кнопка (chevron), открывающая лист (sheet)
  «App Tools» со списком модулей: название, короткое описание, число инструментов, тумблер. Под строкой «App» —
  «N of M modules on». Серверы MCP — как сейчас, тумблером.

### Поиск
- `search_tools` ищет только среди скрытых инструментов (имя инструмента начинается с `_`, или сервер «по
  требованию») во включённых модулях и серверах. Найденные доступны до конца ответа.
- `search_all_tools` ищет среди всех инструментов всех модулей и подключённых серверов — видимых и скрытых,
  включённых и выключенных (кроме самих поисков). Найденные доступны до конца ответа.
- Отбор кандидатов — чистая функция `ToolCatalog.candidates(_ all: [String: MCPManager.Function], scope: .hidden | .all,
  disabled: Set<String>, onDemand: Set<String>) -> [String: String]` (имя → summary).
- Описания: `search_tools` — «найди инструмент, которого нет в списке: редкие инструменты приложения (чаты,
  модели, MCP-серверы, уведомления, окна, библиотеки) и серверов по требованию; если ничего — search_all_tools».
  `search_all_tools` — «ищет по всем инструментам, включая выключенные пользователем; только когда search_tools
  не нашёл».
- Записка о недостающей команде (`missingCommandNote`) просит вызвать `glasschat___app_alert`; этот инструмент
  сразу считается найденным для ответа.

## 4. `app_visualize`

### Инструмент
- `app_visualize(html: string, libraries?: [string], height?: number, title?: string)`.
  `html` — содержимое `<body>` (разметка, `<style>`, `<script>`). `libraries` — имена из списка ниже.
  `height` — высота в пикселях; без неё — по содержимому. `title` — короткая подпись (для доступности и карточки).
- Перед ответом модели страница один раз рендерится скрыто (до 3 с): результат «Shown.» или
  «Shown, but the page reported errors: … — call app_visualize again with a fix.».
- Ответ инструмента не содержит HTML; HTML хранится в аргументах вызова (как сейчас, в `chats.json`).

### Показ
- Чат (`MessageRow`): под карточкой вызова — `VisualizationView`, ширина сообщения, высота = `height` или по
  содержимому, не больше 640.
- Ноч (`AssistantNotchContent`): та же вью под текстом ответа, не больше 260 по высоте.
- Страница: `<!doctype html>` + `<meta charset>` + общий стиль `glass.css` + `<script src>` библиотек + `html` +
  скрипт, сообщающий высоту (`ResizeObserver`) и ошибки (`window.onerror`, `unhandledrejection`).
- Чистая функция `VisualPage.html(body:libraries:)` собирает страницу.

### Песочница
- `WKWebView` с `WKWebsiteDataStore.nonPersistent()`; JS включён, окна не открываются.
- `WKContentRuleList` блокирует все загрузки `http`, `https`, `file`: сеть недоступна.
- Навигация разрешена только для первой загрузки; ссылки не открываются.
- Библиотеки отдаёт `WKURLSchemeHandler` схемы `glasschat-viz` (`glasschat-viz://lib/<name>/<file>`) только
  из папок библиотек. Из страницы в приложение — только сообщения `height` и `error`.

### Библиотеки
- `VisualLibraries` (`@MainActor`, Observable): манифест `libraries.json` в
  `~/Library/Application Support/GlassChat/libraries/`; запись: `name`, `version`, `files` (относительные пути;
  `.js` подключаются `<script>`, `.css` — `<link>`), `global`, `purpose`, `bundled`.
- В бандле (`Resources/Visualize/`, офлайн): **Chart.js 4.4.x** (`chart.umd.min.js`, `Chart`, графики),
  **Mermaid 11.x** (`mermaid.min.js`, `mermaid`, схемы — элементы `.mermaid` рисуются при загрузке),
  **KaTeX** (уже в `Resources/KaTeX`, `katex`, формулы), плюс `glass.css`.
  Бандл-библиотеки есть в манифесте по умолчанию; удаление прячет их до повторной установки.
- `_app_install_library(package, version?, file?, global?, purpose)`: загрузка с jsDelivr
  (`https://cdn.jsdelivr.net/npm/<package>@<version>/<file>`). Без `file` — точки входа из
  `https://data.jsdelivr.com/v1/packages/npm/<package>@<version>/entrypoints` (js и css). Без `version` — последняя
  (`…/resolved`). Не больше 10 МБ. Проходит `ActionGate` (как `app_bash`: «Download <package> from jsDelivr»).
- `_app_remove_library(name)`: убирает из манифеста; загруженные файлы удаляются.
- Описание `app_visualize` строится из манифеста: каждая библиотека — имя, глобальное имя, назначение.

### Директивы
- В описании `app_visualize`: когда показывать (числа, сравнения, доли, тренды, процессы, шаги, расписания,
  структурированные данные), когда нет (короткий факт, разговор); текстовый ответ остаётся кратким рядом;
  ширина ~600 px в чате и ~460 px в ноче, тёмный фон в ноче; классы `glass.css`; внешние URL заблокированы.
- В промпте ассистента одна строка: числа, сравнения и шаги показывай через `glasschat__app_visualize`
  (небольшая высота в ноче).

## Дополнения (2026-10-25, по просьбе пользователя)
- `app_ask_user` — в `necessary`: не виден в UI, всегда включён.
- Прокрутка: колесо над визуализацией прокручивает её, а у её края (или если она не прокручивается) — чат.
- Длинный диалог: сообщения вне экрана не рендерятся (ленивая колонка), веб-вью визуализаций создаются только для видимых.

## Проверка
Self-test: `WhisperLanguage.hint`; `PromptCache.mark` (anthropic / не anthropic, строки и части, tool-сообщения);
модуль у каждого инструмента, `necessary` всегда предлагается, миграция `"__app__"`; `ToolCatalog.candidates` для
`.hidden` и `.all` (выключенные, по требованию); `VisualPage.html` (скрипты библиотек, стиль, отчёт высоты);
манифест библиотек (кодирование, удаление бандл-библиотеки); URL jsDelivr.
Вживую: короткая русская фраза в Whisper; `cached` > 0 во втором раунде; модули в поповере; поиск скрытого
инструмента; график Chart.js и схема Mermaid в чате и в ноче; ошибка JS возвращается модели; сеть из страницы
заблокирована; установка и удаление библиотеки.

## Вне рамок
- React и сборка JSX.
- Доступ страницы к сети или к файлам.
