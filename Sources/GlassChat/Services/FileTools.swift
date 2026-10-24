import Foundation

/// `app_read`, `app_write`, `app_edit`: files the way Claude Code reads and edits them.
enum FileTools {
    static let defaultLimit = 2000
    static let maxLineLength = 2000
    static let maxEntries = 1000
    static let maxReadBytes = 50_000_000

    /// `~` is the home folder; a relative path starts at the chat's working folder.
    static func resolvePath(_ path: String, cwd: URL) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return FileManager.default.homeDirectoryForCurrentUser }
        if trimmed.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.appending(path: String(trimmed.dropFirst(2))).standardizedFileURL
        }
        if trimmed.hasPrefix("/") { return URL(filePath: trimmed).standardizedFileURL }
        return cwd.appending(path: trimmed).standardizedFileURL
    }

    /// A file as numbered lines (`cat -n`), or a folder as its entries (folders end with "/").
    static func read(_ url: URL, offset: Int?, limit: Int?) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw MCPError(message: "\(url.path) does not exist.")
        }
        if isDirectory.boolValue { return try list(url) }
        // Devices (/dev/zero), pipes and sockets never end: only regular files are read.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw MCPError(message: "\(url.path) is not a regular file.")
        }
        if let size = attributes[.size] as? Int, size > maxReadBytes {
            throw MCPError(message: "\(url.path) is \(size / 1_000_000) MB; read parts of it with app_bash (head, tail, grep).")
        }
        let data = try Data(contentsOf: url)
        if data.prefix(8192).contains(0) { throw MCPError(message: "\(url.path) is a binary file.") }
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        let start = max((offset ?? 1) - 1, 0)
        guard start < lines.count || lines.isEmpty else {
            throw MCPError(message: "\(url.path) has \(lines.count) lines; offset \(offset ?? 1) is past the end.")
        }
        let end = min(start + max(limit ?? defaultLimit, 1), lines.count)
        return (start..<end).map { i in
            var line = lines[i]
            if line.count > maxLineLength { line = String(line.prefix(maxLineLength)) + "…" }
            return String(format: "%6d\t", i + 1) + line
        }.joined(separator: "\n")
    }

    private static func list(_ url: URL) throws -> String {
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let entries = names.prefix(maxEntries).map { name -> String in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.appending(path: name).path, isDirectory: &isDirectory)
            return isDirectory.boolValue ? name + "/" : name
        }
        var text = entries.joined(separator: "\n")
        if names.count > maxEntries { text += "\n… and \(names.count - maxEntries) more" }
        return text.isEmpty ? "(empty folder)" : text
    }

    /// Creates the folders it needs and replaces the file.
    static func write(_ url: URL, content: String) throws -> String {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(content.utf8)
        try data.write(to: url, options: .atomic)
        return "Wrote \(data.count) bytes to \(url.path)."
    }

    /// Exact replacement; several matches need `replaceAll`.
    static func edit(_ url: URL, old: String, new: String, replaceAll: Bool) throws -> String {
        guard old != new else { throw MCPError(message: "old_string and new_string are the same.") }
        guard !old.isEmpty else { throw MCPError(message: "old_string is empty.") }
        let text = try String(contentsOf: url, encoding: .utf8)
        let count = text.components(separatedBy: old).count - 1
        guard count > 0 else { throw MCPError(message: "old_string was not found in \(url.path).") }
        guard count == 1 || replaceAll else {
            throw MCPError(message: "old_string occurs \(count) times in \(url.path); give more context or set replace_all.")
        }
        try Data(text.replacingOccurrences(of: old, with: new).utf8).write(to: url, options: .atomic)
        return count == 1 ? "Replaced 1 occurrence." : "Replaced \(count) occurrences."
    }
}
