import AppKit
import ApplicationServices
import Observation

/// The talk shortcut from any app. Modifiers alone cannot be registered as a hot key, so the keyboard is watched
/// with an event tap, which needs Accessibility access. The tap also keeps a shortcut's key (⌥⇧Space, F5) from
/// reaching the app in front while it is held.
@Observable
@MainActor
final class TalkKey {
    static let shared = TalkKey()

    /// macOS lets the app see the keyboard of other apps.
    private(set) var trusted = AXIsProcessTrusted()
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    /// Esc pressed in any app (the open notch folds).
    var onEscape: (() -> Void)?

    private var shortcut: Shortcut?
    private var tracker: PushToTalk.Tracker?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var trustWatch: Task<Void, Never>?
    /// The shortcut's key went down as part of it: its repeats stay from the app until it is up, even after a
    /// modifier let go ended the phrase.
    private var keyDown = false

    private init() {}

    /// Watches for the shortcut instead of the previous one; nil stops.
    func register(_ shortcut: Shortcut?) {
        unregister()
        guard let shortcut else { return }
        self.shortcut = shortcut
        tracker = PushToTalk.Tracker(shortcut)
        let defaults = UserDefaults.standard
        if !trusted, !defaults.bool(forKey: "accessibilityAsked") {
            defaults.set(true, forKey: "accessibilityAsked")
            // macOS shows its prompt once; Settings shows the state after that.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        }
        guard installTap() else {
            watchTrust(shortcut)
            return
        }
        trusted = true
    }

    func unregister() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
        trustWatch?.cancel()
        trustWatch = nil
        // A phrase being held ends with nothing sent.
        if tracker?.isHeld == true { onCancel?() }
        tracker = nil
        shortcut = nil
        keyDown = false
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Without Accessibility access there is no tap; it is made once access is given.
    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: { _, type, event, _ in
            // Added to the main run loop: called on the main thread.
            let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let flags = UInt(event.flags.rawValue)
            let pass = MainActor.assumeIsolated { TalkKey.shared.handle(type, keyCode: keyCode, isRepeat: isRepeat, flags: flags) }
            return pass ? Unmanaged.passUnretained(event) : nil
        }, userInfo: nil) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func watchTrust(_ shortcut: Shortcut) {
        trustWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if AXIsProcessTrusted() {
                    self.register(shortcut)
                    return
                }
            }
        }
    }

    /// Whether the event goes on to the app: only the shortcut's own key while it is held is kept from it.
    private func handle(_ type: CGEventType, keyCode: UInt32, isRepeat: Bool, flags: UInt) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        guard var tracker, let shortcut else { return true }
        let edge: PushToTalk.Edge?
        switch type {
        case .flagsChanged:
            edge = tracker.flagsChanged(NSEvent.ModifierFlags(rawValue: flags))
        case .keyDown:
            edge = tracker.keyDown(keyCode, isRepeat: isRepeat)
            // Esc alone (⌘Esc and the like are other shortcuts).
            if keyCode == 53, edge == nil, !tracker.isHeld,
               NSEvent.ModifierFlags(rawValue: flags).intersection(Shortcut.relevant).isEmpty { onEscape?() }
        case .keyUp:
            edge = tracker.keyUp(keyCode)
        default:
            edge = nil
        }
        self.tracker = tracker
        switch edge {
        case .press?: onPress?()
        case .release?: onRelease?()
        case .cancel?: onCancel?()
        case nil: break
        }
        guard shortcut.keyCode == keyCode else { return true }
        if type == .keyDown, tracker.isHeld { keyDown = true }
        let ownKey = keyDown || (type == .keyUp && edge == .release)
        if type == .keyUp { keyDown = false }
        return !ownKey
    }
}
