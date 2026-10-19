import Foundation

/// An MCP server as set up in Settings.
struct MCPServer: Identifiable, Codable, Hashable, Sendable {
    enum Transport: String, Codable, Sendable, CaseIterable {
        case stdio, http
    }

    var id = UUID()
    var name: String
    var enabled = true
    var transport: Transport = .stdio
    /// stdio: the command line (`npx -y @modelcontextprotocol/server-filesystem ~/Documents`).
    var command = ""
    /// stdio: extra environment, one `KEY=value` per line.
    var environment = ""
    /// http: the endpoint of a Streamable HTTP server.
    var url = ""
    /// http: extra headers, one `Name: value` per line (e.g. `Authorization: Bearer …`).
    var headers = ""

    init(name: String) {
        self.name = name
    }

    var environmentPairs: [String: String] {
        pairs(environment, separator: "=")
    }

    var headerPairs: [String: String] {
        pairs(headers, separator: ":")
    }

    private func pairs(_ text: String, separator: Character) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let i = line.firstIndex(of: separator) else { continue }
            let key = line[..<i].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }
}
