import AppKit
import SwiftUI

@main
struct GlassChatApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        #if DEBUG
        SelfTests.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .newChat, object: nil)
                }
                .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObservation: NSKeyValueObservation?
    /// SwiftUI keeps its own object as NSApp.delegate; this is ours.
    private static weak var current: AppDelegate?

    /// The Dock icon of the current appearance (an icns has no dark variant without an asset catalog).
    private func updateDockIcon() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let url = Bundle.main.url(forResource: dark ? "AppIcon-Dark" : "AppIcon-Light", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate()
        Self.current = self
        updateDockIcon()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in AppDelegate.current?.updateDockIcon() }
        }
        MCPManager.shared.syncConnections()
        // Voice models a previous version never downloaded (a new install gets them in the onboarding).
        if AppSettings.shared.isConfigured, !VoiceModels.shared.isComplete {
            VoiceModels.shared.startDownloads()
        }
        NotchPanelController.shared.content = { AnyView(AssistantNotchContent()) }
        AssistantController.shared.attach(NotchPanelController.shared.model)
        if AppSettings.shared.assistantEnabled { NotchPanelController.shared.install() }
        GlobalHotKey.shared.action = { NotchPanelController.shared.toggle() }
        Self.registerShortcut()
        #if DEBUG
        if ProcessInfo.processInfo.environment["GLASSCHAT_NOTCH_DEMO"] == "1" { NotchDemo.start() }
        #endif
        NotificationCenter.default.addObserver(forName: .assistantToggled, object: nil, queue: .main) { _ in
            Task { @MainActor in
                if AppSettings.shared.assistantEnabled { NotchPanelController.shared.install() } else { NotchPanelController.shared.uninstall() }
                AppDelegate.registerShortcut()
            }
        }
    }

    /// The notch's shortcut, while the notch is on.
    static func registerShortcut() {
        let settings = AppSettings.shared
        GlobalHotKey.shared.register(settings.assistantEnabled ? settings.assistantShortcut : nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ChatStore.shared.saveNow()
    }

    /// With the notch assistant the app keeps running without windows; the Dock icon opens one again.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppSettings.shared.assistantEnabled
    }
}

extension Notification.Name {
    static let newChat = Notification.Name("GlassChat.newChat")
}

#if DEBUG
/// GLASSCHAT_NOTCH_DEMO=1: the notch's face and bars go through every mood, to look at them.
@MainActor
enum NotchDemo {
    static func start() {
        let model = NotchPanelController.shared.model
        let moods: [(AssistantAvatar.Mood, Waveform.Mode)] = [(.idle, .idle), (.listening, .input), (.thinking, .wave), (.speaking, .output), (.error, .idle)]
        Task { @MainActor in
            var i = 0
            while true {
                (model.mood, model.wave) = moods[(i / 60) % moods.count]
                model.level = 0.5 + 0.5 * sin(Double(i) / 3)
                i += 1
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }
}
#endif
