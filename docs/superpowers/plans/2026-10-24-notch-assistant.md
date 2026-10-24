# Голосовой ассистент в ноче и visualize — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GlassChat получает голосового агента, который живёт на месте ноча MacBook (слушает, сам ловит конец фразы, распознаёт, отвечает с инструментами, говорит, задаёт вопросы), а во второй фазе — инструмент `app_visualize` для HTML-визуализаций в чате и в ноче.

**Architecture:** Прозрачная неактивирующая `NSPanel` над ночем с SwiftUI-формой, которая морфится между состояниями. `AssistantController` — машина состояний голосового цикла поверх `VoiceRecorder` (AVAudioEngine + `SilenceDetector`), `TranscriptionSession` (SpeechAnalyzer или `/audio/transcriptions`) и общего `ChatController.shared`. Новые инструменты — кейсы `AppTool` (`app_say`, `app_ask_user`, `app_visualize`), их UI (`QuestionCard`, `VisualizeView`) общий для ноча и окна.

**Tech Stack:** Swift 6.2 (strict concurrency), SwiftUI + AppKit (`NSPanel`, `NSHostingView`), AVFAudio (`AVAudioEngine`, `AVSpeechSynthesizer`, `AVAudioPlayer`), Speech (`SpeechAnalyzer`, `SpeechTranscriber`, `DictationTranscriber`, `AssetInventory`), WebKit (`WKWebView`), MarkdownUI (vendored).

**Spec:** `docs/superpowers/specs/2026-10-24-notch-assistant-design.md` — читать вместе с планом; числа и поведение берутся оттуда.

## Global Constraints

- macOS 26+, сборка только с `--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`; никаких `#Preview`, `@Entry` и других макросов с плагинами (в т.ч. Swift Testing — не собирается с CLT).
- Swift 6 strict concurrency: модели `Sendable`; сервисы состояния — `@Observable @MainActor final class` с `static let shared`.
- Новых удалённых зависимостей нет; `Vendor/` не трогать.
- Текст интерфейса — на английском, как в остальном приложении (Speak, Stop Speaking, Stop, Open in Window, New Conversation, Other…, Skip, Back, Next, Confirm, Cancel).
- Имена инструментов: `glasschat__app_say`, `glasschat__app_ask_user`, `glasschat__app_visualize` (префикс `MCPManager.registryPrefix`, группа `AppTool.key`).
- Комментарии и стиль — как в окружающем коде: короткие `///` над типами и неочевидными функциями, английский.
- Визуальные значения (размеры, отступы, тайминги анимаций) провизорные: `DESIGN.md` в проекте нет (уровень дизайн-системы L0); они взяты из спецификации или выбраны здесь и могут меняться после ревью пользователя.
- Работа в ветке `feature/notch-assistant`; коммит после каждой задачи, сообщение заканчивается строкой `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Проверка чистой логики: `scripts/selftest.sh` (Задача 1) → `SELF-TEST: all N passed`, код 0. Проверка UI: `scripts/bundle.sh --open` и ручные сценарии.
- После Задачи 10 — **стоп**: показать пользователю фазу 1 и ждать правок, Задачи 11–12 только после его «продолжаем».

## Review Focus

1. **Клики рядом с ночем, когда он закрыт** (пункты меню-бара, статус-иконки под прозрачной частью панели) должны доходить до других приложений → ручная проверка в Задаче 7, шаг 6.
2. **Русская речь с распознаванием Apple** — `SpeechTranscriber` не знает `ru_RU`, должен сработать `DictationTranscriber` и показать живой текст → Задача 9, шаг 5, сценарий «ru».
3. **Чат ассистента удалён из сайдбара**, пока ноч открыт или ответ идёт → следующий клик создаёт новый чат «Assistant», без падения → Задача 9, шаг 5, сценарий «deleted».
4. **Повторные клики** по ночу/аватару во время записи, распознавания или ответа не запускают второй цикл и не ломают состояние → Задача 9, шаг 5, сценарий «double».
5. **Смена экранов** (внешний монитор без ноча, закрытая крышка, смена разрешения) → панель переезжает, на экране без ноча — пилюля 180 pt → Задача 7, шаг 6.

---

## Фаза 1

### Task 1: Self-test, общий ChatController, контекст чата ассистента

**Files:**
- Create: `Sources/GlassChat/Debug/SelfTests.swift`, `Sources/GlassChat/Debug/SelfTests+Context.swift`, `scripts/selftest.sh`
- Create: `Sources/GlassChat/Services/ContextWindow.swift`, `Sources/GlassChat/Services/AssistantPrompt.swift`
- Modify: `Sources/GlassChat/App/GlassChatApp.swift` (вызов self-test в `init`), `Sources/GlassChat/Services/ChatController.swift`, `Sources/GlassChat/Services/AppSettings.swift`, `Sources/GlassChat/Views/RootView.swift`

**Interfaces:**
- Produces:
  - `SelfTests.expect(_ condition: Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line)`; каждая задача добавляет `extension SelfTests { static func <area>() }` в свой файл `Debug/SelfTests+<Area>.swift` и регистрирует её в `SelfTests.suites`.
  - `ChatController.shared` (инициализатор `private`).
  - `enum ContextWindow { static func slice(_ messages: [Message], limit: Int) -> [Message] }`.
  - `enum AssistantPrompt { static let standard: String; static func effective(_ custom: String) -> String }` (пустой/пробельный `custom` → `standard`).
  - `AppSettings`: `assistantEnabled: Bool = true`, `transcriptionModel: String = ""`, `transcriptionLanguage: String = ""` (идентификатор локали, пусто = системная), `silencePause: Double = 1.5`, `followUpWindow: Double = 15`, `speechWait: Double = 8`, `assistantContextLimit: Int = 16`, `systemVoice: String = ""` (идентификатор `AVSpeechSynthesisVoice`), `ttsModel: String = ""`, `ttsVoice: String = "alloy"`, `assistantPrompt: String = ""`, `assistantChatID: Chat.ID?` (хранится строкой UUID). Ключи `UserDefaults` = имена свойств.

- [ ] **Step 1: Каркас self-test**

`SelfTests` — `@MainActor enum` под `#if DEBUG`; `runIfRequested()` ничего не делает без `GLASSCHAT_SELF_TEST=1`, иначе прогоняет `suites`, печатает `SELF-TEST: all N passed` или `SELF-TEST: K of N failed` + строки провалов (`file:line name`) и вызывает `exit(0/1)`. Вызов — первой строкой `GlassChatApp.init()` под `#if DEBUG`. `scripts/selftest.sh` (zsh, `set -euo pipefail`, `cd` в корень, как `bundle.sh`): `swift build --sdk "$SDK"`, затем `GLASSCHAT_SELF_TEST=1 "$(swift build --sdk "$SDK" --show-bin-path)/GlassChat"`. Сделать исполняемым.

- [ ] **Step 2: Написать проверки среза контекста** в `SelfTests+Context.swift` (`static func context()`), сообщения строятся хелпером из строки ролей (`"uaua"` → user/assistant):

```swift
expect(ContextWindow.slice(msgs("uaua" * 5), limit: 0).count == 20, "limit 0 keeps all")
expect(ContextWindow.slice(msgs("uaua" * 5), limit: 16).count == 16, "limit 16 of 20")
expect(ContextWindow.slice(msgs("uaua" * 5), limit: 16).first?.role == .user, "starts with user")
expect(ContextWindow.slice(msgs("uaua"), limit: 3).map(\.role) == [.user, .assistant], "assistant at cut is dropped")
expect(ContextWindow.slice(msgs("uau"), limit: 1).map(\.role) == [.user], "limit 1 keeps the question")
expect(ContextWindow.slice(msgs("uau"), limit: 5).count == 3, "shorter than limit")
expect(AssistantPrompt.effective("  ") == AssistantPrompt.standard, "blank prompt = standard")
expect(AssistantPrompt.effective("Be brief") == "Be brief", "custom prompt kept")
```

- [ ] **Step 3: Запустить** `scripts/selftest.sh` — ожидается ошибка компиляции (`cannot find 'ContextWindow' in scope`).

- [ ] **Step 4: Реализовать** `ContextWindow.slice` (последние `limit` сообщений; пока первое — не `.user`, отбрасывать его; `limit <= 0` → все), `AssistantPrompt` (текст `standard` — английский, по §3 спецификации: ассистент в ноче MacBook, пользователь говорит голосом, распознавание может ошибаться; отвечать очень коротко, на языке пользователя; говорить вслух через `glasschat__app_say`, когда просят или уместна короткая реплика; уточнять через `glasschat__app_ask_user`, когда есть понятные варианты; **без** упоминания visualize — его добавит Задача 11), поля `AppSettings` (в `init` читать из `UserDefaults`, `didSet` пишет, как у существующих полей).

- [ ] **Step 5: Встроить в `ChatController`**: `static let shared = ChatController()`, `private init()`. В `send`: `let isAssistant = id == settings.assistantChatID`; после общего системного промпта, если `isAssistant`, добавить system-сообщение `AssistantPrompt.effective(settings.assistantPrompt)`; история = `ContextWindow.slice(сообщения без плейсхолдера ответа, limit: isAssistant ? settings.assistantContextLimit : 0)`. `RootView`: `private let controller = ChatController.shared` вместо `@State … = ChatController()`.

- [ ] **Step 6: Проверить**: `scripts/selftest.sh` → `SELF-TEST: all 8 passed`; `scripts/bundle.sh --open` — обычный чат отвечает как раньше.

- [ ] **Step 7: Commit** — `git add` перечисленные файлы, `git commit -m "Add self-tests, shared chat controller and assistant chat context limit"`.

### Task 2: Вкладка настроек «Assistant»

**Files:**
- Create: `Sources/GlassChat/Views/AssistantSettings.swift`
- Modify: `Sources/GlassChat/Views/SettingsView.swift`

**Interfaces:**
- Consumes: поля `AppSettings` из Задачи 1, `AssistantPrompt.standard`.
- Produces: `struct AssistantSettings: View`; уведомление `Notification.Name.assistantToggled` (object: nil), которое шлёт переключатель — Задача 7 ставит/убирает панель по нему.

- [ ] **Step 1: Реализовать `AssistantSettings`** — `Form` `.formStyle(.grouped)`, секции:
  - **Notch Assistant**: `Toggle("Assistant in the Notch")` (на `onChange` — `post(.assistantToggled)`); footer «Click the notch to talk. Closing the window keeps GlassChat running while this is on.»
  - **Listening**: `TextField("Transcription Model", prompt: "whisper-1")` + footer «Empty: on-device Apple recognition.»; `Picker("Language")` — «System» + локали `DictationTranscriber.supportedLocales` (загрузка в `.task`, сортировка по `Locale.current.localizedString(forIdentifier:)`), выключен, когда модель задана; «Pause that ends a phrase» 0.5…5 с шагом 0.1; «Keep listening after an answer» 0…60 с шагом 1; «Messages sent to the model» 0…200 с footer «0: the whole chat.» Поля-числа — как `Tools per search` в `SettingsView` (TextField + Stepper, с ограничением в `onChange`).
  - **Voice**: `Picker("macOS Voice")` — «System Default» + `AVSpeechSynthesisVoice.speechVoices()` (имя + язык), выключен, когда TTS-модель задана; `TextField("TTS Model", prompt: "gpt-4o-mini-tts")`; `TextField("TTS Voice", prompt: "alloy")` — только если TTS-модель не пустая; footer «Empty model: the macOS voice.»
  - **Prompt**: `TextEditor` над `assistantPrompt` высотой 120; пока пусто — серый текст `AssistantPrompt.standard` поверх (overlay, `allowsHitTesting(false)`); кнопка «Reset» очищает поле.
  - `DisclosureGroup("Advanced")`: «Wait for speech after a click» 2…30 с шагом 1 (`speechWait`).
- [ ] **Step 2:** `SettingsView`: `Tab("Assistant", systemImage: "waveform") { AssistantSettings() }` после «Prompt»; высоту окна настроек поднять до 560.
- [ ] **Step 3: Проверить**: `scripts/bundle.sh --open`, ⌘, → вкладка Assistant: значения по умолчанию 1.5 / 15 / 16 / 8, Advanced раскрывается, после перезапуска значения сохраняются, Reset возвращает серый текст.
- [ ] **Step 4: Commit** — `"Add Assistant settings tab"`.

### Task 3: Детекция тишины и запись микрофона

**Files:**
- Create: `Sources/GlassChat/Services/Voice/SilenceDetector.swift`, `Sources/GlassChat/Services/Voice/VoiceRecorder.swift`, `Sources/GlassChat/Debug/SelfTests+Silence.swift`
- Modify: `Resources/Info.plist`, `Sources/GlassChat/Debug/SelfTests.swift` (регистрация)

**Interfaces:**
- Produces:
  - `struct SilenceDetector { struct Config: Sendable { var calibration = 0.3; var startMargin = 12.0; var startHold = 0.15; var endMargin = 6.0; var silence = 1.5; var maxPhrase = 60.0; var wait = 8.0 }; enum Event: Equatable { case speechStarted, phraseEnded, noSpeech }; init(_ config: Config); mutating func feed(_ db: Double, at time: TimeInterval) -> Event? }` — `db` в dBFS, `time` — секунды от начала записи.
  - `struct Recording: Sendable { let url: URL; let duration: TimeInterval }` — WAV 16 кГц моно 16 бит во временной папке (`glasschat-phrase-<uuid>.wav`).
  - `enum VoiceError: LocalizedError { case microphoneDenied, noInput, languageUnsupported(String), engine(String) }` — `errorDescription` по-английски («GlassChat needs the microphone: System Settings → Privacy & Security → Microphone.», «No microphone was found.», «Apple recognition does not know <locale>. Set a transcription model in Settings → Assistant.», текст движка).
  - `@Observable @MainActor final class VoiceRecorder { static let shared; private(set) var level: Double /* 0…1 = (dB + 60) / 50, обрезано */; private(set) var isRecording: Bool; static func requestAccess() async -> Bool; func inputFormat() throws -> AVAudioFormat; func record(_ config: SilenceDetector.Config, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws -> Recording?; func cancel() }` — `record` возвращает запись по `phraseEnded`, `nil` по `noSpeech` или `cancel()`.

- [ ] **Step 1: Проверки детектора** (`static func silence()`). Хелпер `run(_ segments: [(db: Double, seconds: Double)], wait: Double = 8) -> [(SilenceDetector.Event, TimeInterval)]` кормит детектор шагом 0.02 с и записывает момент каждого события. Хелпер `near(_ got:, _ want: [(SilenceDetector.Event, TimeInterval)]) -> Bool` сравнивает события по порядку с допуском ±0.03 с. Событие приходит в момент, когда условие выполнилось (начало речи — после `startHold`):

```swift
expect(near(run([(-60, 1), (-30, 0.5), (-60, 2)]), [(.speechStarted, 1.15), (.phraseEnded, 3.0)]), "phrase with 1.5 s pause")
expect(near(run([(-60, 0.5), (-30, 0.1), (-60, 9)]), [(.noSpeech, 8.0)]), "blip is not speech; wait 8 s")
expect(near(run([(-60, 16)], wait: 15), [(.noSpeech, 15.0)]), "follow-up window 15 s")
expect(near(run([(-60, 0.5), (-30, 61)]), [(.speechStarted, 0.65), (.phraseEnded, 60.5)]), "phrase capped at 60 s")
// фон поднялся до -50 (ниже порога -48) — порог едет за ним
expect(near(run([(-60, 1), (-50, 3), (-35, 0.5), (-45, 2)]), [(.speechStarted, 4.15), (.phraseEnded, 6.0)]), "floor adapts")
// после речи -50 выше фон+6 = -54 — это ещё не тишина
expect(near(run([(-60, 1), (-30, 0.5), (-50, 3), (-60, 2)]), [(.speechStarted, 1.15), (.phraseEnded, 6.0)]), "hysteresis")
```

- [ ] **Step 2: Запустить** `scripts/selftest.sh` — ошибка компиляции (`SilenceDetector` нет).
- [ ] **Step 3: Реализовать `SilenceDetector`:**
  - пока `time < calibration` — фон = среднее уровней, событий нет;
  - вне речи: уровень выше `фон + startMargin` непрерывно `startHold` → `speechStarted`, начало речи — момент первого превышения; иначе фон = `фон·0.95 + db·0.05`;
  - речь не началась к `time ≥ wait` → `noSpeech` (один раз);
  - в речи фон заморожен; уровень ниже `фон + endMargin` непрерывно `silence` → `phraseEnded`; `time − начало речи ≥ maxPhrase` → `phraseEnded`.
- [ ] **Step 4: Запустить** — `all N passed`.
- [ ] **Step 5: Реализовать `VoiceRecorder`:**
  - `requestAccess` — `AVAudioApplication.requestRecordPermission()`;
  - tap 1024 кадра на `inputNode`. На аудиопотоке tap: RMS → dBFS (минимум −100); буфер через `AVAudioConverter` в 16 кГц моно Int16 → `AVAudioFile`; `onBuffer(buffer)` с исходным буфером;
  - уровень и время по счётчику кадров (`frames / sampleRate`) отдаются в `MainActor`, где кормят детектор и обновляют `level`;
  - событие или `cancel()` останавливают движок и снимают tap;
  - если `inputNode` без каналов → `VoiceError.noInput`.
- [ ] **Step 6:** `Info.plist`: `NSMicrophoneUsageDescription` = «GlassChat listens to what you say to the assistant in the notch.», `NSSpeechRecognitionUsageDescription` = «GlassChat turns what you say to the assistant into text on this Mac.»
- [ ] **Step 7: Проверить**: `scripts/selftest.sh` → все проходят; `scripts/bundle.sh` собирается. (Живая запись проверяется в Задаче 9.)
- [ ] **Step 8: Commit** — `"Add silence detection and microphone recording"`.

### Task 4: Распознавание — Apple и API

**Files:**
- Create: `Sources/GlassChat/Services/Voice/Transcriber.swift`, `Sources/GlassChat/Services/MultipartForm.swift`, `Sources/GlassChat/Debug/SelfTests+Multipart.swift`
- Modify: `Sources/GlassChat/Services/OpenAIClient.swift`, `Sources/GlassChat/Debug/SelfTests.swift`

**Interfaces:**
- Consumes: `Recording`, `VoiceError`, `AppSettings.transcriptionModel/transcriptionLanguage`.
- Produces:
  - `struct MultipartForm { init(boundary: String = "GlassChat-\(UUID().uuidString)"); mutating func add(_ name: String, _ value: String); mutating func add(file name: String, filename: String, mimeType: String, data: Data); var contentType: String; var body: Data }`.
  - `OpenAIClient.transcribe(wav: Data, model: String, language: String?) async throws -> String` — `POST audio/transcriptions`, поля `model`, `language` (если есть), файл `file` = `speech.wav`/`audio/wav`; ответ `{"text": …}`; ошибки через существующий `check`.
  - `@MainActor protocol TranscriptionSession: AnyObject { nonisolated func append(_ buffer: AVAudioPCMBuffer); func finish(_ recording: Recording) async throws -> String; func cancel() }` — `append` зовётся с аудиопотока.
  - `enum Transcription { @MainActor static func start(inputFormat: AVAudioFormat, onPartial: @escaping @MainActor (String) -> Void, onProgress: @escaping @MainActor (Double?) -> Void) async throws -> any TranscriptionSession }` — модель задана → `APITranscription`, иначе `AppleTranscription`.

- [ ] **Step 1: Проверки multipart** (`static func multipart()`), `MultipartForm(boundary: "B")`, поле `model=whisper-1`, файл `Data("RIFF".utf8)`:

```swift
expect(form.contentType == "multipart/form-data; boundary=B", "content type")
expect(text.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n"), "field part")
expect(text.contains("--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n"), "file part")
expect(text.hasSuffix("--B--\r\n"), "closing boundary")
```

- [ ] **Step 2: Запустить** — ошибка компиляции. **Step 3:** реализовать `MultipartForm`. **Step 4:** запустить — проходят.
- [ ] **Step 5: `OpenAIClient.transcribe`** — запрос через существующий `request(_:method:)`, `Content-Type` = `form.contentType`. `language` для API = `languageCode` из настройки языка (или текущей локали).
- [ ] **Step 6: `AppleTranscription`:**
  - **Локаль** = `transcriptionLanguage` или `Locale.current`. Модуль:
    - если `SpeechTranscriber.supportedLocale(equivalentTo:)` не `nil` → `SpeechTranscriber(locale:, preset: .progressiveTranscription)`;
    - иначе если `DictationTranscriber.supportedLocale(equivalentTo:)` не `nil` → `DictationTranscriber(locale:, preset: .progressiveShortDictation)`;
    - иначе `VoiceError.languageUnsupported(locale.identifier)`.
  - **Ассеты:** если `AssetInventory.status(forModules:) != .installed` — `assetInstallationRequest(supporting:)`; `downloadAndInstall()`, `onProgress(progress.fractionCompleted)` опросом 0.2 с; по окончании `onProgress(nil)`.
  - **Анализ:** формат = `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`; `AsyncStream<AnalyzerInput>` + `SpeechAnalyzer(modules:)` + `start(inputSequence:)`. Задача читает `results` модуля (две ветки `switch` по типу модуля): финальные куски копятся, `onPartial(final + volatile)`.
  - **`append`:** конвертирует буфер в формат анализатора (`AVAudioConverter`) и кладёт в continuation — только `Sendable`-состояние, класс `@unchecked Sendable` с замком, как `ResumeOnce`.
  - **`finish`:** `continuation.finish()`, `finalizeAndFinishThroughEndOfInput()`, дождаться задачи результатов, вернуть обрезанный текст. **`cancel`:** закрыть поток и отменить задачу.
- [ ] **Step 7: `APITranscription`** — `append` пустой; `finish` читает WAV и зовёт `transcribe` с `AppSettings.normalizedBaseURL`/`token`.
- [ ] **Step 8: Проверить**: `scripts/selftest.sh`, `scripts/bundle.sh` собираются. (Живое распознавание — Задача 9.)
- [ ] **Step 9: Commit** — `"Add Apple and API speech transcription"`.

### Task 5: Озвучка — Speaker, `app_say`, кнопка Speak

**Files:**
- Create: `Sources/GlassChat/Services/Voice/Speaker.swift`, `Sources/GlassChat/Services/SpeechText.swift`, `Sources/GlassChat/Debug/SelfTests+SpeechText.swift`
- Modify: `Sources/GlassChat/Services/OpenAIClient.swift`, `Sources/GlassChat/Services/AppTools.swift`, `Sources/GlassChat/Views/MessageRow.swift`, `Sources/GlassChat/Debug/SelfTests.swift`

**Interfaces:**
- Produces:
  - `enum SpeechText { static func plain(_ markdown: String) -> String }`.
  - `OpenAIClient.speech(_ text: String, model: String, voice: String) async throws -> Data` — `POST audio/speech`, JSON `{model, input, voice, response_format: "mp3"}`.
  - `@Observable @MainActor final class Speaker { static let shared; private(set) var isSpeaking: Bool; private(set) var level: Double /* 0…1 */; private(set) var speakingID: String?; func speak(_ text: String, id: String? = nil) async throws; func stop() }` — возвращается по окончании или `stop()`; отмена задачи вызывает `stop()` (`withTaskCancellationHandler`); новый `speak` прерывает текущий.
  - `AppTool.say = "app_say"`.

- [ ] **Step 1: Проверки** (`static func speechText()`):

```swift
expect(SpeechText.plain("# Title\n**bold** and `code` [link](http://x)") == "Title\nbold and code link", "markup removed")
expect(SpeechText.plain("Before\n```swift\nlet x = 1\n```\nAfter") == "Before\nAfter", "code blocks dropped")
expect(SpeechText.plain("- one\n- two") == "one\ntwo", "bullets removed")
expect(SpeechText.plain("![img](a.png) $x^2$ ~~old~~ _it_") == "x^2 old it", "images, math, strike, italics")
```

- [ ] **Step 2: Запустить** — ошибка компиляции. **Step 3:** реализовать `SpeechText.plain` регулярными выражениями (`NSRegularExpression`/`Regex`): блоки кода → удалить, картинки → удалить, ссылки → текст, маркеры `#`, `- `/`* `/`1. ` в начале строки, `**`, `*`, `_`, `~~`, `` ` ``, `$` → удалить, пустые строки схлопнуть, `trim`. **Step 4:** запустить — проходят.
- [ ] **Step 5: `Speaker`:**
  - **TTS-модель пуста:** `AVSpeechUtterance(string:)`, голос `systemVoice` или голос текущей локали (`AVSpeechSynthesisVoice(language:)`). `AVSpeechSynthesizer.write(_:toBufferCallback:)` → буферы в `AVAudioPlayerNode` своего `AVAudioEngine`; RMS буфера → `level`; конец — пустой буфер (длина 0) после последнего запланированного.
  - **TTS-модель задана:** `speech(...)` → `AVAudioPlayer(data:)`, `isMeteringEnabled`, таймер 30 Гц: `averagePower` → `level`; конец — делегат `audioPlayerDidFinishPlaying`.
  - Ошибки API пробрасываются как `APIError`.
- [ ] **Step 6: `app_say`** в `AppTool`: описание «Say a text aloud to the user (the macOS voice, or the TTS model from Settings). Returns when it has been spoken.»; параметры `text` (required). `perform`: пустой текст → `MCPError("A \"text\" is needed.")`; `try await Speaker.shared.speak(text)`; вернуть `"Spoken."`, а если был `stop()` или отмена — `"Stopped by the user."`.
- [ ] **Step 7: Кнопка в `MessageRow`** (ассистент, hover-панель, рядом с Copy): `action(speaking ? "Stop Speaking" : "Speak", speaking ? "stop.fill" : "speaker.wave.2", …)`, где `speaking = Speaker.shared.speakingID == message.id.uuidString`. Озвучивается `SpeechText.plain` всех текстов шагов + `content`. Ошибка → `controller.errors[chatID] = APIError(status: nil, message: error.localizedDescription, url: nil)`. То же действие в контекстном меню.
- [ ] **Step 8: Проверить**: `scripts/selftest.sh`; `scripts/bundle.sh --open`.
  - В обычном чате: «скажи вслух привет» — модель вызывает `app_say`, слышен голос, карточка инструмента — «Spoken.».
  - Кнопка Speak на ответе — читает без разметки; повторное нажатие — тишина.
  - Stop во время `app_say` — голос замолкает, результат «Stopped by the user.».
  - С TTS-моделью `gpt-4o-mini-tts` — голос через API.
- [ ] **Step 9: Commit** — `"Add text to speech, the app_say tool and a Speak button"`.

### Task 6: Вопросы пользователю — `app_ask_user`

**Files:**
- Create: `Sources/GlassChat/Services/QuestionCenter.swift`, `Sources/GlassChat/Views/QuestionCard.swift`, `Sources/GlassChat/Debug/SelfTests+AskUser.swift`
- Modify: `Sources/GlassChat/Services/AppTools.swift`, `Sources/GlassChat/Services/ChatController.swift`, `Sources/GlassChat/Views/MessageRow.swift`, `Sources/GlassChat/Debug/SelfTests.swift`

**Interfaces:**
- Produces:
  - `struct AskOption: Sendable, Hashable { let label: String; let description: String? }`, `struct AskQuestion: Sendable, Hashable { let question: String; let header: String?; let options: [AskOption]; let multiSelect: Bool }`, `enum AskAnswer: Sendable, Hashable { case skipped, one(String), many([String]) }`.
  - `enum AskUser { static func parse(_ args: JSONValue) throws -> [AskQuestion]; static func result(_ questions: [AskQuestion], _ answers: [AskAnswer]) -> String }` — 1–4 вопроса, у каждого непустой `question` и 1–6 вариантов, иначе `MCPError` с понятным текстом; `result` — компактный JSON `{"answers":[{"question":…,"answer":…}]}` (`skipped` → `null`, `many` → массив).
  - `struct PendingQuestions: Sendable { let callID: String; let questions: [AskQuestion]; var index = 0; var answers: [AskAnswer]; var isReviewing: Bool; mutating func answer(_ a: AskAnswer); mutating func back() }` — `answers` изначально все `.skipped`; `answer` пишет в `answers[index]` и сдвигает `index`; в режиме сводки — ничего; `back` — `max(index − 1, 0)`.
  - `@Observable @MainActor final class QuestionCenter { static let shared; private(set) var pending: [Chat.ID: PendingQuestions]; func ask(_ questions: [AskQuestion], callID: String, in chat: Chat.ID) async throws -> [AskAnswer]?; func answer(_ a: AskAnswer, in chat: Chat.ID); func back(in chat: Chat.ID); func confirm(in chat: Chat.ID); func dismiss(in chat: Chat.ID) }` — `nil` = отменено (Cancel, Stop, удаление чата); второй `ask` в том же чате, пока первый ждёт, бросает `MCPError("Another question is waiting for the user; ask all questions in one call.")`.
  - `AppTool.run(_:chatID:callID:controller:)` — новый параметр `callID: String` (передаётся из `ChatController`).
  - `struct QuestionCard: View { let chatID: Chat.ID }`.

- [ ] **Step 1: Проверки** (`static func askUser()`):

Хелпер `args(questions: Int, options: Int, text: String? = "Q")` строит `{"questions":[…]}` с заданным числом вопросов и вариантов (`text == nil` — без поля `question`).

```swift
let ok = JSONValue.parse(#"{"questions":[{"question":"Format?","header":"Fmt","options":[{"label":"PDF","description":"print"},{"label":"MD"}],"multi_select":true}]}"#)!
expect((try? AskUser.parse(ok))?.first?.options.count == 2 && (try? AskUser.parse(ok))?.first?.multiSelect == true, "parses")
expect((try? AskUser.parse(args(questions: 1, options: 2, text: nil))) == nil, "question required")
expect((try? AskUser.parse(args(questions: 1, options: 0))) == nil, "at least one option")
expect((try? AskUser.parse(args(questions: 1, options: 7))) == nil, "at most six options")
expect((try? AskUser.parse(args(questions: 5, options: 2))) == nil, "at most four questions")
expect((try? AskUser.parse(args(questions: 4, options: 6)))?.count == 4, "limits are inclusive")
let r = JSONValue.parse(AskUser.result(qs3, [.one("PDF"), .skipped, .many(["a", "b"])]))!
expect(r["answers"]?.array?[0]["answer"]?.string == "PDF" && r["answers"]?.array?[1]["answer"] == .null
       && r["answers"]?.array?[2]["answer"]?.array?.count == 2, "result shape")
var p = PendingQuestions(callID: "c", questions: qs3)   // index 0
p.answer(.one("PDF")); p.back(); expect(p.index == 0, "back")
p.back(); expect(p.index == 0, "back at first stays")
p.answer(.one("x")); p.answer(.skipped); p.answer(.one("y")); expect(p.isReviewing, "review after last")
p.answer(.one("z")); expect(p.answers[2] == .one("y"), "no answers in review")
```

- [ ] **Step 2: Запустить** — ошибка компиляции. **Step 3:** реализовать типы, `AskUser`, `PendingQuestions`. **Step 4:** запустить — проходят.
- [ ] **Step 5: `QuestionCenter`** — `ask` кладёт `PendingQuestions`, ждёт через `withCheckedContinuation` + `ResumeOnce`; `withTaskCancellationHandler` → `dismiss`. `confirm` возвращает `answers`, `dismiss` возвращает `nil`; оба убирают запрос.
- [ ] **Step 6: Инструмент** `AppTool.askUser = "app_ask_user"`:
  - описание: «Ask the user one to four questions with suggested answers and wait for their choice. They pick an option, type their own answer, or skip. Use it instead of asking in text when there are clear options.»;
  - параметры — схема из спецификации §4 (`questions[]` с `question`, `header`, `options[{label, description}]`, `multi_select`);
  - `perform`: `parse` → `ask` → `nil` бросает `MCPError("The user dismissed the questions.")`, иначе `AskUser.result`.
  - `ChatController`: передать `call.id` в `tool.run`; в `delete(_:)` — `QuestionCenter.shared.dismiss(in: id)`.
- [ ] **Step 7: `QuestionCard`** — читает `QuestionCenter.shared.pending[chatID]`.
  - **Вопрос:** сверху capsule с `header` и «1/3» (caption, secondary); `question` (headline). Варианты — строки-кнопки на всю ширину: label + description (secondary); при `multiSelect` — галочки и кнопка «Next» (`.many(выбранные)`).
  - **Свой ответ:** поле «Other…» (`onSubmit` → `.one(текст)`, при `multiSelect` текст добавляется к выбранным).
  - **Низ:** «Back» (выключена на первом), «Skip», «Cancel».
  - **Сводка:** список «вопрос — ответ / Skipped», кнопки «Back», «Cancel», «Confirm» (`.glassProminent`, `.keyboardShortcut(.defaultAction)`).
  - Фон и рамка — как у `ToolCallCard` (secondary 0.08, радиус 12, рамка 0.15), `maxWidth: 560`.
- [ ] **Step 8: `MessageRow`** — после `ToolCallsGroup(calls:)` шага: если `QuestionCenter.shared.pending[chatID]?.callID` есть среди `step.calls` → `QuestionCard(chatID: chatID)`.
- [ ] **Step 9: Проверить**: `scripts/selftest.sh`; `scripts/bundle.sh --open`.
  - В обычном чате: «спроси меня через ask_user про формат и срок отчёта» — карточка в ленте.
  - Проверить вариант, свой ответ, Skip, Back, Confirm — модель получает JSON и отвечает по нему.
  - Повторить с Cancel — модель видит «dismissed».
  - Нажать Stop во время карточки — карточка исчезает, вызов «Stopped.».
- [ ] **Step 10: Commit** — `"Add the app_ask_user tool and question card"`.

### Task 7: Панель в ноче — геометрия, форма, окно, жизненный цикл

**Files:**
- Create: `Sources/GlassChat/Views/Notch/NotchGeometry.swift`, `Sources/GlassChat/Views/Notch/NotchShape.swift`, `Sources/GlassChat/Views/Notch/NotchPanel.swift`, `Sources/GlassChat/Views/Notch/NotchView.swift`, `Sources/GlassChat/App/MainWindow.swift`, `Sources/GlassChat/Debug/SelfTests+Notch.swift`
- Modify: `Sources/GlassChat/App/GlassChatApp.swift`, `Sources/GlassChat/Views/RootView.swift`, `Sources/GlassChat/Debug/SelfTests.swift`

**Interfaces:**
- Consumes: `AppSettings.assistantEnabled`, `.assistantToggled`.
- Produces:
  - `enum NotchState: Equatable { case closed, busy, hover, expanded }`.
  - `enum NotchGeometry { static let expandedWidth: CGFloat = 480; static let maxExpandedHeight: CGFloat = 520; static func notchRect(screenFrame: CGRect, safeAreaTop: CGFloat, auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?, menuBarHeight: CGFloat) -> CGRect; static func shapeSize(_ state: NotchState, notch: CGSize, contentHeight: CGFloat) -> CGSize; @MainActor static func screen() -> NSScreen? }`.
  - `@Observable @MainActor final class NotchModel { var notchSize: CGSize; var isExpanded: Bool; var isHovering: Bool; var isBusy: Bool; var hasUnread: Bool; var contentHeight: CGFloat; var state: NotchState { get }; var shapeSize: CGSize { get }; var onExpand: (() -> Void)?; var onCollapse: (() -> Void)?; func expand(); func collapse() }` — `state`: expanded → hover → busy (если `isBusy || hasUnread`) → closed.
  - `@MainActor final class NotchPanelController { static let shared; let model: NotchModel; func install(); func uninstall() }`.
  - `@MainActor enum MainWindow { static var open: OpenWindowAction?; static var pendingChat: Chat.ID?; static func show(_ chat: Chat.ID) }`.
  - `NotchView(model:content:)` — форма + слот `content` (тело раскрытого ноча), заполняет Задача 9; до неё — `Text("GlassChat")`.

- [ ] **Step 1: Проверки геометрии** (`static func notch()`):

```swift
let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 32, auxiliaryLeftWidth: 662, auxiliaryRightWidth: 662, menuBarHeight: 32)
       == CGRect(x: 662, y: 950, width: 188, height: 32), "hardware notch")
expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
       == CGRect(x: 666, y: 958, width: 180, height: 24), "pill uses menu bar height")
expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 0).height == 32, "pill default 32")
let n = CGSize(width: 188, height: 32)
expect(NotchGeometry.shapeSize(.closed, notch: n, contentHeight: 300) == n, "closed")
expect(NotchGeometry.shapeSize(.hover, notch: n, contentHeight: 0) == CGSize(width: 260, height: 36), "hover +36/side +4")
expect(NotchGeometry.shapeSize(.busy, notch: n, contentHeight: 0) == CGSize(width: 244, height: 32), "busy +28/side")
expect(NotchGeometry.shapeSize(.expanded, notch: n, contentHeight: 200) == CGSize(width: 480, height: 232), "expanded fits")
expect(NotchGeometry.shapeSize(.expanded, notch: n, contentHeight: 900).height == 520, "expanded max")
```

- [ ] **Step 2: Запустить** — ошибка компиляции. **Step 3:** реализовать `notchRect` (ноч: ширина = `frame.width − left − right`, x = `frame.minX + left`, y = `frame.maxY − safeAreaTop`; пилюля 180 × (menuBar > 0 ? menuBar : 32) по центру), `shapeSize`, `screen()` (экран с `safeAreaInsets.top > 0`, иначе `NSScreen.main`; menu bar = `frame.maxY − visibleFrame.maxY`). **Step 4:** запустить — проходят.
- [ ] **Step 5: Форма, панель, модель:**
  - **`NotchShape`:**
    - `Shape` с `bottomRadius` (closed/busy/hover 10, expanded 24) и `earRadius` 6;
    - верх прямой на всю ширину; вогнутые «ушки» радиуса `earRadius` в верхних углах; бока вертикальные, отступ `earRadius` внутрь; низ скруглён `bottomRadius`;
    - `animatableData` = `bottomRadius`.
  - **`NotchPanel`** (`NSPanel`):
    - `[.borderless, .nonactivatingPanel]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`;
    - `level = .init(rawValue: NSWindow.Level.mainMenu.rawValue + 3)`;
    - `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`;
    - `canBecomeKey = true`, `canBecomeMain = false`.
    - **Размер:** ширина `max(480, ноч + 72)`, высота 520 + 8; верх к верху экрана, центр по ночу.
  - **`NotchView`:** чёрная `NotchShape` размером `model.shapeSize`, прижата к верху по центру, `.animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.state)`. Тап по форме при не-expanded → `model.expand()`. `.environment(\.colorScheme, .dark)`. Content виден только в expanded (`.transition(.opacity)`); его высота через `onGeometryChange` → `model.contentHeight`.
  - **`NotchPanelController`:**
    - **`install`:** панель + `NSHostingView`, позиция, `orderFrontRegardless()`;
    - **`mouseMoved`** (глобальный + локальный монитор): кадр формы в координатах экрана с запасом 4 pt → `ignoresMouseEvents = !inside`, `model.isHovering = inside` (только не в expanded);
    - **`leftMouseDown`** (глобальный): в expanded и вне формы → `collapse()`;
    - **`keyDown`** (локальный): Esc (53) в expanded → `collapse()`, событие съедается;
    - **смена экранов:** `didChangeScreenParametersNotification` → пересчёт `notchSize` и позиции;
    - **`uninstall`:** убрать мониторы и панель.
- [ ] **Step 6: Жизненный цикл и главное окно:**
  - `AppDelegate.applicationDidFinishLaunching`: если `assistantEnabled` → `install()`; на `.assistantToggled` — `install`/`uninstall` по значению.
  - `applicationShouldTerminateAfterLastWindowClosed` → `!AppSettings.shared.assistantEnabled`.
  - `WindowGroup(id: "main")`. В `RootView` — `@Environment(\.openWindow)`; в `onAppear` записать `MainWindow.open`; если есть `MainWindow.pendingChat` — выбрать его и очистить.
  - `MainWindow.show(chat)`: `NSApp.activate()`. Если есть видимое окно, которое `canBecomeMain` и не `NSPanel`, → `post(.selectChat, chat)`; иначе `pendingChat = chat` и `open?(id: "main")`.
- [ ] **Step 7: Проверить** (`scripts/selftest.sh`, затем `scripts/bundle.sh --open`):
  1. Форма сливается с ночем; наведение — подрастает; клик — раскрывается до 480 pt с «GlassChat»; Esc и клик мимо — сворачивается.
  2. **(Review Focus 1)** При закрытом ноче пункты меню-бара и статус-иконки рядом с ночем кликаются; приложение под раскрытой панелью вне формы тоже кликается.
  3. Полноэкранное приложение и другой Space — ноч на месте.
  4. Закрыть главное окно — приложение живо, клик по Dock открывает окно; выключить ассистента в настройках — панель исчезает, закрытие окна завершает приложение.
  5. **(Review Focus 5)** Подключить внешний монитор / сменить разрешение — панель на встроенном экране на месте; без встроенного экрана — пилюля 180 pt по центру главного.
- [ ] **Step 8: Commit** — `"Add the notch panel"`.

### Task 8: Аватар и визуализация звука

**Files:**
- Create: `Sources/GlassChat/Views/Notch/AssistantAvatar.swift`, `Sources/GlassChat/Views/Notch/Waveform.swift`
- Modify: `Sources/GlassChat/Views/Notch/NotchView.swift` (шапка + DEBUG-демо)

**Interfaces:**
- Produces:
  - `struct AssistantAvatar: View { enum Mood: Equatable { case idle, listening, thinking, speaking, error }; let mood: Mood; let level: Double; var size: CGFloat = 28 }`.
  - `struct Waveform: View { enum Mode: Equatable { case idle, input, wave, output }; let mode: Mode; let level: Double; var bars = 6; var maxHeight: CGFloat }` — хранит историю последних `bars` значений `level` (`onChange`).
  - `NotchView` получает параметры шапки: `NotchView(model:mood:level:wave:content:)`; шапка видна в hover/busy (размер 20) и expanded (28).

- [ ] **Step 1: Реализовать `AssistantAvatar`** — `TimelineView(.animation)` + `Canvas`. Значения (провизорные):
  - **Тело:** белый `RoundedRectangle(cornerRadius: size·0.32, style: .continuous)`.
  - **Глаза:** чёрные эллипсы `size·0.14 × size·0.22` в точках x ±`size·0.18`, y −`size·0.04`.
  - **idle:** дыхание — масштаб 1 ± 0.03, период 3.5 с; моргание — высота глаз → 0.02 на 0.12 с каждые случайные 3–6 с.
  - **listening:** scaleY `1 + level·0.12`, scaleX `1 − level·0.05`, сдвиг вверх `level·3`.
  - **thinking:** глаза смещены на (+`size·0.06`, −`size·0.08`); 3 белые точки (60 %) диаметром `size·0.08` по орбите радиуса `size·0.62`, период 1.2 с.
  - **speaking:** чёрная капсула-рот шириной `size·0.26`, высотой `size·(0.04 + level·0.14)`, y +`size·0.2`.
  - **error:** глаза — дуги вниз (штрих 2), покачивание ±4°, период 2 с.
- [ ] **Step 2: Реализовать `Waveform`.** Полоски шириной 3, промежуток 3, радиус 1.5, белые, высота 4…`maxHeight`.
  - `input`/`output`: высоты по истории уровня.
  - `wave`: `0.5 + 0.5·sin(t·6 + i·0.8)`.
  - `idle`: все 4.
- [ ] **Step 3: Шапка в `NotchView`** — HStack: аватар слева с отступом 12, `Spacer` шириной ноча, `Waveform` справа с отступом 12, высота ноча. Под `#if DEBUG`, при `GLASSCHAT_NOTCH_DEMO=1`, `GlassChatApp` подаёт демо-данные: moods и режимы по кругу каждые 2 с, `level` синусом.
- [ ] **Step 4: Проверить**: `GLASSCHAT_NOTCH_DEMO=1` + debug-бинарник (`swift build --sdk …` и запуск из `--show-bin-path`): раскрыть ноч — пять настроений по очереди без рывков, полоски реагируют; в hover/busy — мини-версии внутри «крыльев».
- [ ] **Step 5: Commit** — `"Add the assistant avatar and waveform"`.

### Task 9: AssistantController и содержимое ноча

**Files:**
- Create: `Sources/GlassChat/Services/AssistantController.swift`, `Sources/GlassChat/Views/Notch/AssistantNotchContent.swift`
- Modify: `Sources/GlassChat/Views/Notch/NotchPanel.swift` (связка модели с контроллером), `Sources/GlassChat/Views/Notch/NotchView.swift` (убрать демо-данные из реального пути), `Sources/GlassChat/Views/MarkdownMessage.swift` (необязательный компактный размер)

**Interfaces:**
- Consumes: всё из Задач 1, 3–8.
- Produces:
  - `@Observable @MainActor final class AssistantController { static let shared; enum Phase: Equatable { case idle, listening(followUp: Bool), transcribing, answering, speaking }; private(set) var phase: Phase; private(set) var heard: String; private(set) var error: String?; private(set) var microphoneDenied: Bool; private(set) var downloadProgress: Double?; private(set) var hasUnreadAnswer: Bool; var chatID: Chat.ID { get } /* создаёт чат при необходимости */; var mood: AssistantAvatar.Mood { get }; var waveMode: Waveform.Mode { get }; var level: Double { get }; var isBusy: Bool { get }; func expanded(); func collapsed(); func listen(); func stopAll(); func newConversation(); func speakLastAnswer() }`.
  - `MarkdownMessage(text:compact:)` — `compact: Bool = false`; при `true` — `.markdownTextStyle(\.text) { FontSize(NSFont.systemFontSize) }`.

- [ ] **Step 1: Цикл в `AssistantController`** (поведение — спецификация §3):
  - **`chatID`:** `assistantChatID`, если такой чат есть в `ChatStore`; иначе новый чат (модель по умолчанию, заголовок «Assistant»), id сохраняется.
  - **`listen(followUp:)`:**
    - выйти, если фаза не `idle` и нет ожидающего вопроса в `chatID`;
    - `requestAccess` → нет → `microphoneDenied = true`, `error = VoiceError.microphoneDenied`;
    - `Transcription.start(...)` (`onPartial` → `heard`, `onProgress` → `downloadProgress`); фаза `.listening(followUp)`;
    - `recorder.record(Config(silence: silencePause, wait: followUp ? followUpWindow : speechWait), onBuffer: session.append)`;
    - `nil` → `session.cancel()`, `idle`.
  - **После записи:** `transcribing` → `finish` → удалить WAV.
    - Пустой текст → `listen` с тем же `followUp`.
    - Есть ожидающий вопрос → `QuestionCenter.shared.answer(.one(text), in: chatID)`.
    - Иначе `ChatController.shared.send(text, in: chatID)`; фаза `answering`.
  - **Ожидание конца ответа:** цикл каждые 100 мс, пока `ChatController.shared.isStreaming(chatID)`. В цикле:
    - появился вопрос и ноч раскрыт → `listen(followUp: true)` в режиме ответа на вопрос (не выходя из ожидания ответа);
    - вопрос пришёл при свёрнутом ноче → `NotchPanelController.shared.model.expand()`.
  - **После ответа:** пока `Speaker.shared.isSpeaking` — фаза `speaking`.
    - Ноч раскрыт → `listen(followUp: true)`.
    - Иначе `hasUnreadAnswer = true`, `idle`.
  - **Ошибки:** `VoiceError`/`APIError` → `error`, `idle`. После ответа `ChatController.shared.errors[chatID]` → `error`.
  - **`expanded()`:** `hasUnreadAnswer = false`, `error = nil`; если `idle` и ответ не идёт — `listen()`.
  - **`collapsed()`:** отменить запись и сессию, `Speaker.stop()`; фаза = `answering`, если ответ идёт, иначе `idle`.
  - **`stopAll()`:** `collapsed()` + `ChatController.shared.stop(chatID)` + `QuestionCenter.shared.dismiss(in: chatID)` → `idle`.
  - **`newConversation()`:** `stopAll()`, новый чат «Assistant» → `assistantChatID`, `heard = ""`.
  - **`speakLastAnswer()`:** переключает озвучку последнего ответа чата (`SpeechText.plain`, `id` = id сообщения).
  - **`mood`:**
    - `error != nil` → `.error`;
    - `listening` → `.listening`;
    - `transcribing`/`answering` → `.thinking`;
    - `speaking` или `Speaker.isSpeaking` → `.speaking`;
    - иначе `.idle`.
  - **`waveMode`:** аналогично (`input` / `wave` / `output` / `idle`).
  - **`level`:** recorder или speaker.
  - **`isBusy`:** `phase != .idle || Speaker.shared.isSpeaking`.
- [ ] **Step 2: Связка** в `NotchPanelController.install`: `model.onExpand = { AssistantController.shared.expanded() }`, `onCollapse = { …collapsed() }`; `isBusy`/`hasUnread` модели следуют контроллеру (`withObservationTracking` в цикле или передача через `NotchView`); шапка получает `mood`/`level`/`waveMode`. Тап по аватару в expanded → `listen()`. При `hasUnread` в свёрнутом ноче справа вместо полосок — белая точка 6 pt, пульсирующая (opacity 0.4…1, период 1.2 с).
- [ ] **Step 3: `AssistantNotchContent`** — тело раскрытого ноча, отступы 12, промежуток 8, `ScrollView` (высота ≤ 520 − ноч − кнопки). Показывается последний обмен чата ассистента:
  - `heard` или последнее сообщение пользователя (callout, белый 55 %);
  - `downloadProgress` → `ProgressView(value:)` «Downloading the speech model…»;
  - чипы шагов последнего ответа: капсулы `hammer` + `call.tool`, спиннер, пока нет результата;
  - текст ответа — `MarkdownMessage(text:compact: true)`;
  - `QuestionCard(chatID:)`, если ждёт;
  - строка ошибки (оранжевый треугольник + текст), при `microphoneDenied` — кнопка «Open Privacy Settings» (`x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`);
  - нижняя строка иконок (белый 70 %, `help` = название): Speak/Stop Speaking (`speaker.wave.2` / `stop.fill`), Stop (`stop.circle`, активна при `isBusy`), Open in Window (`arrow.up.forward.app` → `MainWindow.show(chatID)`), New Conversation (`plus.bubble`).
- [ ] **Step 4: Убрать** демо-данные из реального пути (`GLASSCHAT_NOTCH_DEMO` остаётся только под `#if DEBUG`).
- [ ] **Step 5: Проверить** (`scripts/bundle.sh --open`, звуковая модель пуста):
  1. Клик → фраза по-английски → через ~1,5 с тишины текст и ответ в ноче; в сайдбаре чат «Assistant».
  2. **ru (Review Focus 2):** язык System (ru) — фраза по-русски, живой текст появляется во время речи, ответ по-русски; при первом запуске — прогресс загрузки модели.
  3. После ответа заговорить в пределах 15 с — новый цикл без клика; молчать 15 с — idle. После клика молчать 8 с — idle; поменять «Wait for speech» на 4 — idle через 4 с.
  4. Свернуть во время ответа — мини-аватар «думает»; по завершении — пульс «готово»; раскрыть — ответ виден, запись началась.
  5. «Скажи вслух …» → аватар говорит, полоски — по голосу, микрофон молчит; потом дослушивание.
  6. Вопрос `ask_user` в ноче: карточка, ответ голосом попадает в «свой вариант», Confirm.
  7. Лимит 2 в настройках, спросить про сообщение 3 шага назад — модель его не видит; 0 — видит.
  8. Звуковая модель `whisper-1` — распознавание через API, без живого текста.
  9. **deleted (Review Focus 3):** удалить чат «Assistant» в сайдбаре во время ответа и после — следующий клик создаёт новый, без падения.
  10. **double (Review Focus 4):** быстрые двойные клики по ночу и аватару во время записи/распознавания/ответа — один цикл, фаза не ломается.
  11. Отказать в доступе к микрофону (`tccutil reset Microphone dev.lixelv.glasschat`, затем «Don't Allow») — грустный аватар, текст и рабочая кнопка Privacy Settings.
  12. Open in Window при закрытом окне — окно открывается на чате ассистента; New Conversation — новый чат.
- [ ] **Step 6: Commit** — `"Add the notch voice assistant"`.

### Task 10: README и контрольная точка фазы 1

**Files:**
- Modify: `README.md`, `CLAUDE.md` (структура: `Views/Notch/`, `Services/Voice/`, `Debug/`, `scripts/selftest.sh`; строку «Тестов в проекте нет» заменить на описание self-test)

- [ ] **Step 1:** README — раздел «Notch Assistant»: как вызвать, настройки (таблица из §6 спецификации), права, инструменты `app_say` и `app_ask_user`.
- [ ] **Step 2:** `scripts/selftest.sh` → все проходят; `scripts/bundle.sh --open` — быстрый прогон сценариев 1, 3, 5 из Задачи 9.
- [ ] **Step 3: Commit** — `"Document the notch assistant"`.
- [ ] **Step 4: СТОП.** Сообщить пользователю, что фаза 1 готова, перечислить, что проверено, и ждать правок. Правки — отдельными задачами перед фазой 2.

## Фаза 2

### Task 11: `app_visualize`

**Files:**
- Create: `Sources/GlassChat/Services/VisualizeHTML.swift`, `Sources/GlassChat/Views/VisualizeView.swift`, `Sources/GlassChat/Debug/SelfTests+Visualize.swift`
- Modify: `Sources/GlassChat/Services/AppTools.swift`, `Sources/GlassChat/Services/AssistantPrompt.swift`, `Sources/GlassChat/Views/MessageRow.swift`, `Sources/GlassChat/Views/Notch/AssistantNotchContent.swift`, `README.md`, `Sources/GlassChat/Debug/SelfTests.swift`

**Interfaces:**
- Produces:
  - `enum VisualizeHTML { static let heightHandler = "glasschatHeight"; static func document(_ html: String, autoHeight: Bool) -> String; static func arguments(_ json: String) -> (html: String, height: CGFloat?, title: String?)? }`.
  - `struct VisualizeView: NSViewRepresentable { let html: String; let fixedHeight: CGFloat? }` — сама выставляет свою высоту.
  - `struct VisualizeBlock: View { let call: ToolCall }` — подпись `title` (caption, secondary) + `VisualizeView`; пока `call.result == nil` — `ProgressView` «Drawing…».
  - `AppTool.visualize = "app_visualize"`.

- [ ] **Step 1: Проверки** (`static func visualize()`):

```swift
let frag = VisualizeHTML.document("<div>hi</div>", autoHeight: true)
expect(frag.hasPrefix("<!doctype html>") && frag.contains("<body><div>hi</div></body>"), "fragment wrapped")
expect(frag.contains("id=\"glasschat-base\"") && frag.contains("overflow:hidden") && frag.contains("glasschatHeight"), "base css, no scroll, resize script")
let full = VisualizeHTML.document("<html><head><title>x</title></head><body>y</body></html>", autoHeight: false)
expect(full.components(separatedBy: "id=\"glasschat-base\"").count == 2 && full.contains("<title>x</title>") && !full.contains("overflow:hidden"), "injected once into head")
expect(VisualizeHTML.document("<HTML><BODY>y</BODY></HTML>", autoHeight: true).contains("<head><style id=\"glasschat-base\">"), "head created, case-insensitive")
expect(VisualizeHTML.arguments(#"{"html":"<b>a</b>","height":300,"title":"T"}"#)! == ("<b>a</b>", 300, "T"), "args")
expect(VisualizeHTML.arguments(#"{"height":300}"#) == nil, "html required")
expect(VisualizeHTML.arguments(#"{"html":"a","height":0}"#)?.height == nil, "non-positive height ignored")
```

- [ ] **Step 2: Запустить** — ошибка компиляции.
- [ ] **Step 3: Реализовать `VisualizeHTML`.**
  - **Базовый CSS** (точный текст): `:root{color-scheme:light dark}html,body{margin:0;background:transparent;font:13px -apple-system,system-ui,sans-serif}`. При `autoHeight` добавляется `html,body{overflow:hidden}`.
  - **Скрипт:** `new ResizeObserver(()=>webkit.messageHandlers.glasschatHeight.postMessage(document.documentElement.scrollHeight)).observe(document.documentElement)`.
  - **Вставка:** `<style id="glasschat-base">…</style><script>…</script>` сразу после открывающего `<head…>`. Если `<head>` нет, но есть `<html…>` — после него вставляется `<head>…</head>`. Если нет ни того ни другого — обёртка `<!doctype html><html><head><meta charset="utf-8">…</head><body>FRAG</body></html>`. Поиск тегов без учёта регистра.
- [ ] **Step 4: Запустить** — проходят.
- [ ] **Step 5: `VisualizeView`.**
  - **WebView:** `WKWebView`, `setValue(false, forKey: "drawsBackground")`, `underPageBackgroundColor = .clear`. Обработчик `heightHandler` — через слабый прокси в `Coordinator`; высота ограничивается 40…2000 и применяется к `frame`/`intrinsicContentSize`. При `fixedHeight` — фиксированная высота.
  - **Ссылки:** `decidePolicyFor` с `.linkActivated` → `NSWorkspace.shared.open`, `.cancel`. `createWebViewWith` → открыть URL во внешнем браузере, вернуть `nil`.
  - **Перезагрузка:** HTML грузится заново только при его изменении.
- [ ] **Step 6: Инструмент `AppTool.visualize`.**
  - **Описание:** «Show the user an HTML visualization (chart, table, diagram, infographic) inline in the chat. Full HTML with CSS and JavaScript; CDN libraries are allowed. The background is transparent: follow light and dark mode with prefers-color-scheme. The width is the chat's; the height fits the content unless "height" (points) is given.»
  - **Параметры:** `html` (string, required), `height` (number), `title` (string).
  - **`perform`:** пустой `html` → `MCPError("An \"html\" is needed.")`, иначе `"Shown to the user."`.
- [ ] **Step 7: Где показывать.**
  - **`MessageRow`:** после `ToolCallsGroup` шага — `ForEach` по вызовам с именем `MCPManager.registryPrefix + "__" + AppTool.visualize.rawValue`, не `isError` → `VisualizeBlock`, на всю ширину колонки.
  - **`AssistantNotchContent`:** последний такой вызов текущего ответа — над текстом ответа, ширина тела.
  - **`AssistantPrompt.standard`:** добавить предложение «Show numbers, comparisons and structure with glasschat__app_visualize (a compact HTML infographic) instead of long text.»
  - **README:** раздел про `app_visualize`.
- [ ] **Step 8: Commit** — `"Add the app_visualize tool"`.

### Task 12: Проверка фазы 2

- [ ] **Step 1:** `scripts/selftest.sh` → все проходят.
- [ ] **Step 2:** `scripts/bundle.sh --open`:
  1. В обычном чате: «покажи график продаж по месяцам на Chart.js» — график под шагом, высота по содержимому, без внутреннего скролла.
  2. С `height` — фиксированная высота со скроллом.
  3. Светлая и тёмная темы выглядят родными; ссылка внутри открывается в браузере.
  4. Перезапуск — визуализация в истории рисуется снова.
  5. В ноче: «сравни три тарифа» — инфографика в теле ноча.
- [ ] **Step 3:** Сообщить пользователю результат; при успехе — `superpowers:finishing-a-development-branch`.
