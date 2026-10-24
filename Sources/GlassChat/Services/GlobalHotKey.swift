import Carbon.HIToolbox
import Observation

/// The assistant's shortcut from any app: Carbon's `RegisterEventHotKey`, which needs no Accessibility permission.
@Observable
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    /// The shortcut is taken by another app or by macOS.
    private(set) var conflict = false
    var action: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {}

    /// Registers the shortcut instead of the previous one; nil removes it.
    func register(_ shortcut: Shortcut?) {
        unregister()
        guard let shortcut else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in GlobalHotKey.shared.action?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        // "GLCH"
        let id = EventHotKeyID(signature: OSType(0x474C_4348), id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        conflict = status != noErr
        if conflict { hotKey = nil }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        conflict = false
    }
}
