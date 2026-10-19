import Foundation

/// One entry of `mcpServers` (the format of Claude Desktop, Cursor and others):
/// `{"command": "npx", "args": [...], "env": {...}}` for a local server,
/// `{"url": "https://…/mcp", "headers": {...}}` for a remote one; `"disabled": true` keeps it off.
struct MCPServer: Identifiable, Hashable, Sendable {
    enum Transport: String, Sendable {
        case stdio, http
    }

    /// The key in `mcpServers`.
    var name: String
    var enabled: Bool
    var transport: Transport
    var command: String
    var args: [String]
    var env: [String: String]
    var url: String
    var headers: [String: String]

    var id: String { name }

    /// Reads an entry; the error says what is wrong with it.
    init(name: String, config: JSONValue) throws {
        guard case .object(let o) = config else { throw MCPError(message: "\"\(name)\" must be an object") }
        self.name = name
        enabled = { if case .bool(true)? = o["disabled"] { return false }; return true }()
        command = o["command"]?.string ?? ""
        args = try (o["args"]?.array ?? []).map {
            guard let s = $0.string else { throw MCPError(message: "\"\(name)\".args must hold strings") }
            return s
        }
        env = try Self.strings(o["env"], "\(name).env")
        url = o["url"]?.string ?? ""
        headers = try Self.strings(o["headers"], "\(name).headers")
        let type = o["type"]?.string?.lowercased()
        if !url.isEmpty || type == "http" || type == "streamable-http" || type == "sse" {
            guard !url.isEmpty else { throw MCPError(message: "\"\(name)\" needs a \"url\"") }
            transport = .http
        } else {
            guard !command.isEmpty else { throw MCPError(message: "\"\(name)\" needs a \"command\" or a \"url\"") }
            transport = .stdio
        }
    }

    private static func strings(_ value: JSONValue?, _ path: String) throws -> [String: String] {
        guard let value else { return [:] }
        guard case .object(let o) = value else { throw MCPError(message: "\"\(path)\" must be an object") }
        return try o.mapValues {
            guard let s = $0.string else { throw MCPError(message: "\"\(path)\" must hold strings") }
            return s
        }
    }

    /// The command line for the login shell, every part quoted.
    var commandLine: String {
        ([command] + args).map(Self.shellQuote).joined(separator: " ")
    }

    private static func shellQuote(_ s: String) -> String {
        // A leading ~ is left out of the quotes so the shell expands it.
        if s.hasPrefix("~/") { return "~/" + shellQuote(String(s.dropFirst(2))) }
        if !s.isEmpty, s.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=:@+,".contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
