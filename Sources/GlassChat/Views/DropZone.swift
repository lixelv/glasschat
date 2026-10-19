import Observation
import SwiftUI

/// Files dragged over any part of the window: the open chat shows its drop zone and receives them.
@Observable
@MainActor
final class DropZone {
    var isTargeted = false
    /// Set by the chat on screen.
    var receive: (([Attachment]) -> Void)?

    func drop(_ urls: [URL]) -> Bool {
        let imported = urls.filter(\.isFileURL).compactMap { try? AttachmentStore.importFile(at: $0) }
        guard !imported.isEmpty, let receive else { return false }
        withAnimation(.snappy) { receive(imported) }
        return true
    }
}

/// A file opened in Quick Look by a click on it in a chat.
@Observable
@MainActor
final class Preview {
    var url: URL?
}
