import AppKit
import SwiftUI

@main
struct GlassChatApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            Text("GlassChat")
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowToolbarStyle(.unified)

        Settings {
            Text("Settings")
        }
    }
}
