import SwiftUI

// Patched for GlassChat: @Entry needs the SwiftUI macro plugin that ships only with Xcode.
private struct HighlightKey: EnvironmentKey {
    static let defaultValue = Highlight()
}

extension EnvironmentValues {
    var highlight: Highlight {
        get { self[HighlightKey.self] }
        set { self[HighlightKey.self] = newValue }
    }
}
