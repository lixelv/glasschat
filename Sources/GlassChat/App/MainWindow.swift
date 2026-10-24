import AppKit
import SwiftUI

/// Opens the main window on a chat from outside it (the notch), also when every window was closed.
@MainActor
enum MainWindow {
    /// Captured by the first window: it still opens one after that window closed.
    static var open: OpenWindowAction?
    /// The chat a window opened this way selects.
    static var pendingChat: Chat.ID?

    static func show(_ chat: Chat.ID) {
        // The notch never activates the app; plain `activate()` is only a request another active app may turn down.
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        let windows = NSApp.windows.filter { $0.canBecomeMain && !($0 is NSPanel) }
        if let window = windows.first(where: \.isVisible) ?? windows.first(where: \.isMiniaturized) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NotificationCenter.default.post(name: .selectChat, object: chat)
        } else {
            pendingChat = chat
            open?(id: "main")
        }
    }
}
