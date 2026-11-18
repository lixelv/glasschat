# Push-to-talk в ноче и инструменты буфера обмена

Два спека, один план. Проверка — встроенные self-tests (`scripts/selftest.sh`, `Sources/GlassChat/Debug/`)
для чистой логики; остальное — запуском приложения.

## Спек 1: PTT — микрофон только пока зажат shortcut

### Поведение

- **PTT-1** Микрофон ассистента включается **только** пока зажат shortcut разговора. Убираются: авто-слушание при
  раскрытии ноча (клик по ночу/аватару только раскрывает его), окно follow-up после ответа, постоянное слушание
  во время ответа («Interrupt by speaking»), hover-to-talk. Их настройки (`hoverToTalk`, `hoverDelay`,
  `interruptBySpeaking`, `followUpWindow`, `speechWait`) и UI в Settings удаляются.
- **PTT-2** Нажатие shortcut (ноч свёрнут или раскрыт): ноч раскрывается, начинается запись и живое распознавание
  (`heard` показывается как сейчас). Пауза в речи запись **не** заканчивает; заканчивает только отпускание.
- **PTT-3** Отпускание: если записано голоса ≥ `SilenceDetector.minimumVoiced` и распознанный текст — слова
  (`SpeechText.isWords`), фраза отправляется в чат ассистента (с «Audio to the Model» — как сейчас, вложением).
  Иначе **ничего не отправляется**, запись удаляется; если ноч был свёрнут до нажатия — он сворачивается обратно.
- **PTT-4** Нажатие во время ответа (модель пишет и/или голос говорит): ответ и голос **продолжаются**. Как только
  в записи появились осмысленные слова пользователя (`BargeIn.isMeaningful` — не эхо голоса ассистента),
  ответ и голос останавливаются (как при текущем barge-in), а запись идёт дальше до отпускания и по PTT-3
  отправляется следующим сообщением.
- **PTT-5** Если во время ответа shortcut отпущен до того, как пользователь заговорил, — ответ не прерывается,
  ничего не отправляется.
- **PTT-6** Пока на экране карточка вопроса `app_ask_user`, фраза, сказанная с зажатым shortcut, становится ответом
  на вопрос (а не новым сообщением). Без shortcut микрофон не включается и для неё.
- **PTT-7** Совпадение аккорда точное: зажаты ровно модификаторы shortcut (и его клавиша, если она есть).
  Если пока аккорд зажат нажата любая другая клавиша или добавлен ещё модификатор — запись отменяется
  (ничего не отправляется, ответ не трогается): это значит, что пользователь жмёт другой shortcut (⌥⌘Esc и т.п.).
  Автоповтор клавиши аккорда не создаёт новых нажатий.
- **PTT-8** Esc при раскрытом ноче сворачивает его (как сейчас); если идёт запись — она отменяется.
  Старый shortcut открытия/сворачивания ноча (⌥⇧Space, Carbon `GlobalHotKey`) удаляется.
- **PTT-9** Shortcut по умолчанию — **⌥⌘** (только модификаторы). Его можно изменить в Settings: в рекордере
  либо зажать ≥2 модификатора и отпустить (аккорд из модификаторов), либо нажать модификатор(ы)+клавишу
  (или F-клавишу без модификаторов). Esc без модификаторов отменяет запись, крестик убирает shortcut.
  Хранится под новым ключом `talkShortcut`; старый `assistantShortcut` игнорируется.
- **PTT-10** Глобальное отслеживание клавиш требует доступа Accessibility. Пока его нет, приложение один раз
  запрашивает его (`AXIsProcessTrustedWithOptions` с prompt) при включённом ассистенте, а в Settings под
  shortcut видно «Needs Accessibility access» с кнопкой, открывающей нужную панель System Settings.
  Когда доступ появляется, shortcut начинает работать без перезапуска.

### Интерфейс (чистая логика, для тестов)

```swift
// Models/Shortcut.swift — меняется
struct Shortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32?          // nil: аккорд только из модификаторов
    var command, shift, option, control: Bool
    var key: String               // "" для аккорда из модификаторов
    init(keyCode: UInt32?, modifiers: NSEvent.ModifierFlags, key: String)
    static let standard: Shortcut // ⌥⌘, keyCode nil
    var modifiers: NSEvent.ModifierFlags   // [.command, .shift, .option, .control] из флагов
    var display: String           // "⌥ ⌘", "⌃ ⌥ ⇧ ⌘ K" — порядок ⌃ ⌥ ⇧ ⌘, затем key (если есть)
    static func keyName(keyCode: UInt32, characters: String?) -> String       // как сейчас
    /// nil keyCode: нужно ≥2 модификатора; с клавишей: ≥1 модификатор или F1–F12.
    static func isValid(modifiers: NSEvent.ModifierFlags, keyCode: UInt32?) -> Bool
}

// Services/Voice/PushToTalk.swift — новое
enum PushToTalk {
    enum Edge: Equatable { case press, release, cancel }
    /// Состояние аккорда по событиям клавиатуры. Учитываются только .command/.shift/.option/.control.
    struct Tracker {
        init(_ shortcut: Shortcut)
        private(set) var isHeld: Bool
        mutating func flagsChanged(_ modifiers: NSEvent.ModifierFlags) -> Edge?
        mutating func keyDown(_ keyCode: UInt32, isRepeat: Bool) -> Edge?
        mutating func keyUp(_ keyCode: UInt32) -> Edge?
    }
    enum Outcome: Equatable { case send, discard }
    /// PTT-3.
    static func outcome(voiced: TimeInterval, text: String) -> Outcome
    /// PTT-3: свернуть ли ноч обратно после отпускания.
    static func foldsBack(openedByPress: Bool, outcome: Outcome) -> Bool
}
```

`Tracker` (PTT-7):
- аккорд из модификаторов: `press`, когда набор модификаторов стал ровно равен аккорду; `release`, когда
  перестал (отпущен любой из них); `cancel` вместо `release`, если пока держали была нажата любая клавиша
  (`keyDown`) или добавлен лишний модификатор; после `cancel` следующий `press` — только после того, как все
  модификаторы аккорда отпущены и снова зажаты.
- аккорд с клавишей: `press` на `keyDown(keyCode)` при ровно этих модификаторах (не повтор); `release` на
  `keyUp(keyCode)` или когда модификаторы перестали совпадать; `cancel`, если пока держали нажата другая клавиша.
- Каждый `press` сопровождается ровно одним `release` или `cancel`; лишних событий нет.

## Спек 2: CLIP — буфер обмена во встроенных инструментах

- **CLIP-1** `_app_read_clipboard` (без аргументов) возвращает текст из системного буфера обмена.
  Если текста нет — `"The clipboard has no text."` (не ошибка).
- **CLIP-2** `_app_write_clipboard` `{text: string, required}` заменяет содержимое буфера этим текстом
  и возвращает `"Copied to the clipboard."`.
- **CLIP-3** Новый модуль `AppModule.clipboard` (title «Clipboard», summary «Read and replace the clipboard's text»),
  включается/выключается как остальные; оба инструмента скрытые (префикс `_`, находятся через `search_tools`).
  `AppModule.of("glasschat___app_read_clipboard") == .clipboard`.
- **CLIP-4** Описания обоих инструментов и стандартный промпт ассистента (`AssistantPrompt.standard`) говорят:
  трогать буфер обмена только когда пользователь явно просит, самостоятельно не читать и не писать.
  Текущий стандартный промпт уходит в `AssistantPrompt.previous`.
