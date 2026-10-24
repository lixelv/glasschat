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
        NSApp.activate()
        let visible = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }
        if visible {
            NotificationCenter.default.post(name: .selectChat, object: chat)
        } else {
            pendingChat = chat
            open?(id: "main")
        }
    }
}
