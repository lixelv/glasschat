# Тайминги голоса, мягкая анимация, прерывание голосом — план

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Быстрее отвечать после последнего слова, мягче анимировать «думает» и давать перебивать ассистента осмысленной фразой.

**Architecture:** Чистые функции (`PhrasePause`, `Smoothing`, `BargeIn`) с self-test; живая пауза детектора меняется по тексту Apple. Один `AudioEngineHub` с Voice Processing (эхоподавление) для микрофона и озвучки; `AssistantController` держит слушатель прерывания, пока идёт ответ или речь.

**Tech Stack:** Swift 6.2, AVFAudio (`AVAudioEngine`, Voice Processing I/O, `AVAudioPlayerNode`), SwiftUI `TimelineView`/`Canvas`, Supertonic `SynthesisOptions`.

**Spec:** `docs/superpowers/specs/2026-10-25-voice-timing-animation-barge-in-design.md`

## Global Constraints

- Сборка с `--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`, без макросов с плагинами.
- Паузы: база `silencePause` = 0,7 с; законченная фраза 0,5·база/0,7; незаконченная 0,9·база/0,7.
- `app_say` ≤ 200 символов → `SynthesisOptions(quality: .fast)`; иначе `.balanced`.
- Прерывание: голос ≥ 0,4 с; ≥ 2 слов или 1 слово ≥ 3 букв; не шумовая фраза; < 50 % слов (≥ 3 букв) из сказанного ассистентом.
- Настройка `interruptBySpeaking` по умолчанию `true`; текст UI английский.
- Коммит после каждой задачи с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; проверка `scripts/selftest.sh`.

## Review Focus

1. **Ассистент говорит через встроенные динамики** — он не должен прерывать сам себя → Task 3/4, проверка вживую по логу `barge-in`.
2. **Voice Processing недоступен** (внешний интерфейс, ошибка включения) — запись работает, прерывание выключено, без падения → Task 3.
3. **Пользователь замолчал посреди фразы без знака препинания** — ждать 0,9 с, не обрывать → Task 1 (`PhrasePause`).
4. **Прерывание во время карточки подтверждения** — карточка отклоняется, ответ не висит → Task 4.
5. **Отмена/сворачивание ноча во время слушателя прерывания** — запись снята, микрофон не остаётся включённым → Task 4.

---

### Task 1: Умная пауза и быстрый синтез
**Files:** Create `Services/Voice/PhrasePause.swift`, `Debug/SelfTests+Pause.swift`; Modify `Services/Voice/SilenceDetector.swift`, `Services/Voice/VoiceRecorder.swift`, `Services/AssistantController.swift`, `Services/AppSettings.swift`, `Services/Voice/Speaker.swift`, `Views/AssistantSettings.swift`.
**Produces:** `enum PhrasePause { static func seconds(for heard: String, base: TimeInterval) -> TimeInterval }`; `SilenceDetector.setSilence(_:)`; `VoiceRecorder.updateSilence(_:)`.
- [ ] Проверки: `"Привет."`/`"Как дела?"`/`"Ура!"`/`"Ну…"` → 0,5 при базе 0,7; `"Включи свет на"` → 0,9; `""` → 0,7; база 1,4 → 1,0 и 1,8.
- [ ] RED → реализовать; `onPartial` вызывает `recorder.updateSilence(PhrasePause.seconds(for: text, base: settings.silencePause))`; default `silencePause` 0,7; Speaker выбирает quality по длине; подпись в настройках.
- [ ] GREEN; commit.

### Task 2: Мягкая анимация «думает»
**Files:** Create `Views/Notch/Smoothing.swift`, `Debug/SelfTests+Smoothing.swift`; Modify `Views/Notch/AssistantAvatar.swift`, `Views/Notch/Waveform.swift`.
**Produces:** `enum Smoothing { static func step(current: Double, target: Double, dt: Double, time: Double) -> Double }`.
- [ ] Проверки: `step(0, 1, dt: 0.4, time: 0.4)` ≈ 0,632; монотонно, не перелетает при dt ≫ time; `Waveform.height(.wave)` ≤ min + 0,6·range.
- [ ] RED → реализовать: аватар хранит сглаженные параметры (класс-состояние в `@State`, обновляется в `TimelineView` кадре), `thinking` — дыхание 1 ± 0,02 / 2,4 с, глаза по Лиссажу 0,05·size / 3 с, свечение 1,5·size, 0,06–0,16; волна `0.3 + 0.3·sin(t·3 + i·0.8)`; высоты полосок сглаживаются (0,25 с).
- [ ] GREEN; commit.

### Task 3: Общий аудиодвижок с эхоподавлением
**Files:** Create `Services/Voice/AudioEngineHub.swift`; Modify `Services/Voice/VoiceRecorder.swift`, `Services/Voice/Speaker.swift`.
**Produces:** `@MainActor final class AudioEngineHub { static let shared; let engine: AVAudioEngine; private(set) var echoCancellation: Bool; func start() throws; func player(for format: AVAudioFormat) -> AVAudioPlayerNode }`.
- [ ] Реализовать: `setVoiceProcessingEnabled(true)` на `inputNode` до старта (ошибка → `echoCancellation = false`, лог); движок запускается один раз и живёт; `VoiceRecorder` ставит/снимает tap, не останавливая движок; `SynthPlayback` берёт player-узел у хаба (подключение к `mainMixerNode` с форматом буфера) вместо своего движка.
- [ ] Self-test без изменений проходит; `bundle.sh`; вручную — запись и озвучка работают (Task 5). Commit.

### Task 4: Слушатель прерывания
**Files:** Create `Services/Voice/BargeIn.swift`, `Debug/SelfTests+BargeIn.swift`; Modify `Services/AssistantController.swift`, `Services/AppSettings.swift`, `Views/AssistantSettings.swift`, `Services/Voice/Speaker.swift` (сказанный текст ответа).
**Produces:** `enum BargeIn { static func isMeaningful(heard: String, voiced: TimeInterval, spoken: String) -> Bool }`; `AppSettings.interruptBySpeaking`; `Speaker.spokenInAnswer: String` (накапливается за ответ, сбрасывается при `send`).
- [ ] Проверки: `("подожди стоп", 0.3, "")` → false (мало голоса); `("да", 0.8, "")` → false; `("Thank you", 1, "")` → false; `("восемь градусов облачность", 1, "В Таллине восемь градусов, облачность")` → false (эхо); `("подожди, лучше про Париж", 0.9, "В Таллине восемь градусов")` → true; `("стоп", 0.6, "")` → true.
- [ ] RED → реализовать: в `waitForAnswer`, если `interruptBySpeaking` и `AudioEngineHub.echoCancellation`, запускается задача слушателя (запись `wait: .infinity`, `onPartial` проверяет `isMeaningful` с `recorder`-голосом); при срабатывании — `Speaker.stop()`, `ChatController.stop`, `ApprovalCenter.dismiss`, `QuestionCenter.dismiss`, запись доводится до паузы и уходит как следующая фраза (`converse` продолжает с ней, как с `first`); без срабатывания — отмена при конце ответа/речи; сворачивание/Stop отменяют. Не запускать при открытой карточке вопроса. Переключатель в настройках.
- [ ] GREEN; commit.

### Task 5: Проверка
- [ ] `scripts/selftest.sh`; ревью ветки (code-reviewer, свежий агент).
- [ ] Вживую: Supertonic через динамики не прерывает сам себя; фраза поверх речи прерывает; кашель — нет; время от конца фразы до голоса — по логу.
