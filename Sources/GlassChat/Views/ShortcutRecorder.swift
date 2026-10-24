import AppKit
import SwiftUI

/// The notch's shortcut in Settings: click, then press the keys; Esc cancels, the cross removes it.
struct ShortcutRecorder: View {
    @Bindable private var settings = AppSettings.shared
    private var hotKey = GlobalHotKey.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent("Shortcut") {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Button(recording ? "Type a shortcut…" : settings.assistantShortcut?.display ?? "None") {
                        recording ? stop() : start()
                    }
                    .frame(minWidth: 120)
                    if settings.assistantShortcut != nil, !recording {
                        Button("Remove Shortcut", systemImage: "xmark.circle.fill") {
                            settings.assistantShortcut = nil
                            AppDelegate.registerShortcut()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                if hotKey.conflict {
                    Text("Another app or macOS uses this shortcut: choose another.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        // The current shortcut must reach this field, not open the notch.
        GlobalHotKey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = UInt32(event.keyCode)
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53, modifiers.intersection([.command, .option, .control, .shift]).isEmpty {
                stop()
                return nil
            }
            guard Shortcut.isValid(modifiers: modifiers, keyCode: keyCode) else { return nil }
            let key = Shortcut.keyName(keyCode: keyCode, characters: event.charactersIgnoringModifiers)
            settings.assistantShortcut = Shortcut(keyCode: keyCode, modifiers: modifiers, key: key)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        AppDelegate.registerShortcut()
    }
}
