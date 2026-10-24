import Foundation

/// `app_bash`: commands in zsh, each chat with its own working folder.
actor ShellRunner {
    static let shared = ShellRunner()

    private var folders: [Chat.ID: URL] = [:]

    /// The chat's working folder (the home folder at first).
    func workingDirectory(for chat: Chat.ID) -> URL {
        folders[chat] ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
