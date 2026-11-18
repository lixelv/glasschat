import AppKit
import SwiftUI

/// The talk shortcut in Settings: click, then hold modifiers and let go (⌥⌘), or press modifiers with a key;
/// Esc cancels, the cross removes it.
struct ShortcutRecorder: View {
    @Bindable private var settings = AppSettings.shared
    private var talkKey = TalkKey.shared
    @State private var recording = false
    @State private var monitor: Any?
    /// The most modifiers held together while recording: let go, they are the shortcut.
    @State private var held: NSEvent.ModifierFlags = []

    var body: some View {
        LabeledContent("Hold to Talk") {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Button(recording ? (held.isEmpty ? "Type a shortcut…" : Shortcut(keyCode: nil, modifiers: held, key: "").display)
                           : settings.talkShortcut?.display ?? "None") {
                        recording ? stop() : start()
                    }
                    .frame(minWidth: 120)
                    if settings.talkShortcut != nil, !recording {
                        Button("Remove Shortcut", systemImage: "xmark.circle.fill") {
                            settings.talkShortcut = nil
                            AppDelegate.registerShortcut()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                if settings.talkShortcut != nil, !talkKey.trusted {
                    HStack(spacing: 6) {
                        Text("Needs Accessibility access")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open Settings") { talkKey.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        held = []
        // The current shortcut must reach this field, not start listening.
        TalkKey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let modifiers = event.modifierFlags.intersection(Shortcut.relevant)
            if event.type == .flagsChanged {
                if modifiers.isStrictSuperset(of: held) || held.isEmpty {
                    held = modifiers
                } else if !modifiers.isSuperset(of: held) {
                    // A modifier let go: the most held together are the shortcut, if they make one.
                    if Shortcut.isValid(modifiers: held, keyCode: nil) {
                        settings.talkShortcut = Shortcut(keyCode: nil, modifiers: held, key: "")
                        stop()
                    } else if modifiers.isEmpty {
                        held = []
                    }
                }
                return event
            }
            let keyCode = UInt32(event.keyCode)
            if event.keyCode == 53, modifiers.isEmpty {
                stop()
                return nil
            }
            guard Shortcut.isValid(modifiers: modifiers, keyCode: keyCode) else { return nil }
            let key = Shortcut.keyName(keyCode: keyCode, characters: event.charactersIgnoringModifiers)
            settings.talkShortcut = Shortcut(keyCode: keyCode, modifiers: modifiers, key: key)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        held = []
        AppDelegate.registerShortcut()
    }
}
