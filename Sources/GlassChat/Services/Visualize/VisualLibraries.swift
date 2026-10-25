import Foundation
import Observation

/// The script libraries a visualization may use: bundled ones (offline) and ones the model installed.
@Observable
@MainActor
final class VisualLibraries {
    static let shared = VisualLibraries()

    struct Entry: Codable, Equatable, Sendable {
        let name: String
        let version: String
        /// Paths in its folder: `.js` files load as scripts, `.css` as styles, in this order.
        let files: [String]
        /// The global it defines (`Chart`), for the model.
        let global: String?
        /// What it is for, for the model.
        let purpose: String
        /// Part of the app; else downloaded into the libraries folder.
        let bundled: Bool
    }

    private(set) var entries: [Entry] = []

    private init() {}

    func entry(_ name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    /// The folder a library's files are served from.
    func directory(for name: String) -> URL? {
        nil
    }
}
