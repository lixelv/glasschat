import Foundation
import Observation

/// The MCP servers: `{"mcpServers": {...}}` in mcp.json, connected while enabled, their tools offered to the model,
/// plus the built-in registry tools through which the model edits that list.
@Observable
@MainActor
final class MCPManager {
    static let shared = MCPManager()

    struct Tool: Hashable, Sendable {
        let name: String
        let description: String
        let inputSchema: JSONValue
    }

    enum Status: Equatable {
        case off, connecting, connected, failed(String)
    }

    private(set) var servers: [MCPServer] = []
    /// The `mcpServers` object.
    private(set) var config: [String: JSONValue] = [:]
    /// Entries that could not be read.
    private(set) var configErrors: [String] = []
    private(set) var status: [MCPServer.ID: Status] = [:]
    private(set) var tools: [MCPServer.ID: [Tool]] = [:]
    private var transports: [MCPServer.ID: any MCPTransport] = [:]
    /// The configuration each live connection was made from, to reconnect only what changed.
    private var connectedConfig: [MCPServer.ID: MCPServer] = [:]

    private static var fileURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "GlassChat", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "mcp.json")
    }

    private init() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
        if case .object(let root) = json, case .object(let servers)? = root["mcpServers"] {
            load(servers)
        } else if let old = json.array {
            // The list the first MCP version wrote: name, enabled, transport, command line, url, header lines.
            var servers: [String: JSONValue] = [:]
            for entry in old {
                guard let name = entry["name"]?.string else { continue }
                var o: [String: JSONValue] = [:]
                if entry["transport"]?.string == "http" {
                    o["url"] = entry["url"] ?? .string("")
                    o["headers"] = .object(Self.lines(entry["headers"]?.string ?? "", ":").mapValues(JSONValue.string))
                } else {
                    let parts = (entry["command"]?.string ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
                    o["command"] = .string(parts.first ?? "")
                    o["args"] = .array(parts.dropFirst().map(JSONValue.string))
                    let env = Self.lines(entry["environment"]?.string ?? "", "=")
                    if !env.isEmpty { o["env"] = .object(env.mapValues(JSONValue.string)) }
                }
                if case .bool(false)? = entry["enabled"] { o["disabled"] = .bool(true) }
                servers[name] = .object(o)
            }
            load(servers)
            save()
        }
    }

    private static func lines(_ text: String, _ separator: Character) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let i = line.firstIndex(of: separator) else { continue }
            let key = line[..<i].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces) }
        }
        return result
    }

    private func load(_ servers: [String: JSONValue]) {
        config = servers
        configErrors = []
        self.servers = servers.keys.sorted().compactMap { name in
            do { return try MCPServer(name: name, config: servers[name]!) }
            catch { configErrors.append(error.localizedDescription); return nil }
        }
    }

    private static func pretty(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(value)) ?? Data(), as: UTF8.self)
    }

    private func save() {
        try? Data(configText.utf8).write(to: Self.fileURL, options: .atomic)
    }

    // MARK: Registry (Settings and the built-in tools)

    /// What Settings shows: `{"mcpServers": {...}}`, pretty printed.
    var configText: String {
        Self.pretty(.object(["mcpServers": .object(config)]))
    }

    /// Takes the JSON from Settings; throws (and keeps the old list) when it cannot be read.
    func apply(_ text: String) throws {
        guard let json = JSONValue.parse(text) else { throw MCPError(message: "Not valid JSON") }
        guard case .object(let root) = json, case .object(let servers)? = root["mcpServers"] else {
            throw MCPError(message: "Expected {\"mcpServers\": {\"name\": {…}}}")
        }
        for (name, entry) in servers { _ = try MCPServer(name: name, config: entry) }
        load(servers)
        save()
        syncConnections()
    }

    func reconnect(_ id: MCPServer.ID) {
        Task { await disconnect(id); syncConnections() }
    }

    /// Adds, replaces or (nil) removes one entry, checking it first.
    private func setEntry(_ name: String, _ entry: JSONValue?) throws {
        if let entry { _ = try MCPServer(name: name, config: entry) }
        var servers = config
        servers[name] = entry
        load(servers)
        save()
        syncConnections()
    }

    /// The built-in tools: the model reads and edits `mcpServers`.
    enum RegistryTool: String, CaseIterable, Sendable {
        case list = "mcp_registry_list"
        case get = "mcp_registry_get"
        case add = "mcp_registry_add"
        case update = "mcp_registry_update"
        case delete = "mcp_registry_delete"

        var description: String {
            switch self {
            case .list: "List the names of the MCP servers in the registry, with their state."
            case .get: "Read one MCP server entry of the registry by its name."
            case .add: "Add an MCP server to the registry. Fails if the name exists. The config is an mcpServers entry: {\"command\": \"npx\", \"args\": [...], \"env\": {...}} for a local server or {\"url\": \"https://…\", \"headers\": {...}} for a remote one; \"disabled\": true keeps it off."
            case .update: "Replace the entry of an existing MCP server in the registry. Fails if the name does not exist."
            case .delete: "Delete an MCP server from the registry by its name. Fails if the name does not exist."
            }
        }

        var parameters: JSONValue {
            let name: JSONValue = .object(["type": .string("string"), "description": .string("The server's key in mcpServers")])
            let config: JSONValue = .object(["type": .string("object"), "description": .string("The mcpServers entry")])
            switch self {
            case .list:
                return .object(["type": .string("object"), "properties": .object([:])])
            case .get, .delete:
                return .object(["type": .string("object"), "properties": .object(["name": name]), "required": .array([.string("name")])])
            case .add, .update:
                return .object(["type": .string("object"), "properties": .object(["name": name, "config": config]),
                                "required": .array([.string("name"), .string("config")])])
            }
        }
    }

    private func registry(_ tool: RegistryTool, _ args: JSONValue) throws -> String {
        let name = args["name"]?.string?.trimmingCharacters(in: .whitespaces) ?? ""
        if tool != .list, name.isEmpty { throw MCPError(message: "A \"name\" is needed.") }
        switch tool {
        case .list:
            let list: [JSONValue] = config.keys.sorted().map { key in
                let server = servers.first { $0.id == key }
                let state: String = switch status[key] {
                case .connected?: "connected, \(tools[key]?.count ?? 0) tools"
                case .connecting?: "connecting"
                case .failed(let message)?: "failed: \(message)"
                default: server == nil ? "invalid entry" : (server!.enabled ? "not connected" : "disabled")
                }
                return .object(["name": .string(key), "state": .string(state)])
            }
            return Self.pretty(.object(["servers": .array(list)]))
        case .get:
            guard let entry = config[name] else { throw MCPError(message: "There is no MCP server \"\(name)\".") }
            return Self.pretty(.object([name: entry]))
        case .add:
            guard config[name] == nil else { throw MCPError(message: "An MCP server \"\(name)\" already exists; update it instead.") }
            guard let entry = args["config"] else { throw MCPError(message: "A \"config\" is needed.") }
            try setEntry(name, entry)
            return "Added \"\(name)\". It is connecting; its tools are offered from the next message."
        case .update:
            guard config[name] != nil else { throw MCPError(message: "There is no MCP server \"\(name)\"; add it instead.") }
            guard let entry = args["config"] else { throw MCPError(message: "A \"config\" is needed.") }
            try setEntry(name, entry)
            return "Updated \"\(name)\". It reconnects; its tools are offered from the next message."
        case .delete:
            guard config[name] != nil else { throw MCPError(message: "There is no MCP server \"\(name)\".") }
            try setEntry(name, nil)
            return "Deleted \"\(name)\"."
        }
    }

    /// Sets or clears `"disabled"` of an entry (the app tools' enable/disable).
    func setEnabled(_ name: String, _ enabled: Bool) throws {
        guard case .object(var entry)? = config[name] else { throw MCPError(message: "There is no MCP server \"\(name)\"; see app_list_mcp.") }
        if enabled { entry["disabled"] = nil } else { entry["disabled"] = .bool(true) }
        try setEntry(name, .object(entry))
    }

    /// Servers that could not start because their command is missing (npx without Node.js, uvx without uv).
    var missingCommands: [(server: String, command: String)] {
        servers.compactMap { server in
            guard server.transport == .stdio, case .failed(let message)? = status[server.id],
                  message.contains("command not found") || message.contains("No such file") || message.contains("code 127")
            else { return nil }
            return (server.name, server.command)
        }
    }

    // MARK: Connections

    /// Connects enabled servers whose configuration changed and drops the rest.
    func syncConnections() {
        for server in servers {
            if !server.enabled {
                if transports[server.id] != nil { Task { await disconnect(server.id) } }
                status[server.id] = .off
            } else if connectedConfig[server.id] != server || status[server.id] == nil {
                Task { await connect(server) }
            }
        }
        for id in Set(transports.keys).union(status.keys) where !servers.contains(where: { $0.id == id }) {
            Task { await disconnect(id) }
        }
    }

    private func disconnect(_ id: MCPServer.ID) async {
        let transport = transports.removeValue(forKey: id)
        connectedConfig[id] = nil
        tools[id] = nil
        status[id] = nil
        await transport?.close()
    }

    private func connect(_ server: MCPServer) async {
        await disconnect(server.id)
        connectedConfig[server.id] = server
        status[server.id] = .connecting
        do {
            let transport: any MCPTransport
            switch server.transport {
            case .stdio:
                let stdio = try StdioTransport(command: server.commandLine, environment: server.env)
                await stdio.start()
                transport = stdio
            case .http:
                guard let url = URL(string: server.url.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
                    throw MCPError(message: "The URL is not valid")
                }
                transport = HTTPTransport(url: url, headers: server.headers)
            }
            transports[server.id] = transport

            let initialized = try await withTimeout(30) {
                try await transport.request("initialize", params: .object([
                    "protocolVersion": .string("2025-06-18"),
                    "capabilities": .object([:]),
                    "clientInfo": .object(["name": .string("GlassChat"), "version": .string("1.0")]),
                ]))
            }
            if let http = transport as? HTTPTransport, let version = initialized["protocolVersion"]?.string {
                await http.setProtocolVersion(version)
            }
            try await transport.notify("notifications/initialized", params: .object([:]))

            var listed: [Tool] = []
            var cursor: String?
            repeat {
                let params: JSONValue = cursor.map { .object(["cursor": .string($0)]) } ?? .object([:])
                let page = try await withTimeout(30) { try await transport.request("tools/list", params: params) }
                for tool in page["tools"]?.array ?? [] {
                    guard let name = tool["name"]?.string else { continue }
                    listed.append(Tool(name: name, description: tool["description"]?.string ?? "",
                                       inputSchema: tool["inputSchema"] ?? .object(["type": .string("object")])))
                }
                cursor = page["nextCursor"]?.string
            } while cursor != nil

            // A newer configuration may have started meanwhile.
            guard connectedConfig[server.id] == server else { return }
            tools[server.id] = listed
            status[server.id] = .connected
        } catch {
            guard connectedConfig[server.id] == server else { return }
            status[server.id] = .failed(error.localizedDescription)
            if let transport = transports.removeValue(forKey: server.id) { await transport.close() }
        }
    }

    // MARK: Tools for a chat

    /// A function the model may call, and where it goes.
    struct Function: Sendable {
        enum Target: Sendable {
            case server(MCPServer.ID, tool: String)
            case registry(RegistryTool)
            case app(AppTool)
            /// `search_tools`: always offered, never switched off.
            case search
        }

        let definition: JSONValue
        let target: Target
        /// The switch it belongs to: a server's name or `AppTool.key` (nil for the search).
        let group: String?
        /// "server: tool — description", what a search ranks it by.
        let summary: String
    }

    /// The prefix of the built-in functions (shown as "GlassChat" on their cards).
    static let registryPrefix = "glasschat"
    static let searchName = registryPrefix + "__search_tools"

    /// Every function there is: the App tools (with the registry), the tools of every connected server, and the search.
    func allFunctions() -> [String: Function] {
        var result: [String: Function] = [:]
        func add(_ name: String, _ description: String, _ parameters: JSONValue, _ target: Function.Target, group: String?, summary: String) {
            result[name] = Function(definition: Self.function(name, description, parameters), target: target, group: group, summary: summary)
        }
        add(Self.searchName, ToolSearch.description, ToolSearch.parameters, .search, group: nil, summary: "")
        for tool in AppTool.allCases {
            add(Self.registryPrefix + "__" + tool.rawValue, tool.description, tool.parameters, .app(tool),
                group: AppTool.key, summary: "GlassChat: \(tool.rawValue) — \(tool.description)")
        }
        for tool in RegistryTool.allCases {
            add(Self.registryPrefix + "__" + tool.rawValue, tool.description, tool.parameters, .registry(tool),
                group: AppTool.key, summary: "GlassChat: \(tool.rawValue) — \(tool.description)")
        }
        for server in servers where server.enabled && status[server.id] == .connected {
            let prefix = Self.slug(server.name, limit: 20)
            for tool in tools[server.id] ?? [] {
                var name = prefix + "__" + Self.slug(tool.name, limit: 60 - prefix.count)
                var n = 2
                while result[name] != nil { name = String(name.prefix(60)) + "\(n)"; n += 1 }
                let description = tool.description.isEmpty ? "\(tool.name) (\(server.name))" : tool.description
                add(name, description, tool.inputSchema, .server(server.id, tool: tool.name),
                    group: server.id, summary: "\(server.name): \(tool.name) — \(tool.description)")
            }
        }
        return result
    }

    /// What the model is offered: the search, the groups not switched off, and the tools a search found.
    func functions(disabled: Set<String>, found: Set<String> = []) -> [String: Function] {
        allFunctions().filter { name, function in
            guard let group = function.group else { return true }
            return !disabled.contains(group) || found.contains(name)
        }
    }

    private static func function(_ name: String, _ description: String, _ parameters: JSONValue) -> JSONValue {
        .object([
            "type": .string("function"),
            "function": .object(["name": .string(name), "description": .string(description), "parameters": parameters]),
        ])
    }

    /// Calls a tool; the text is the tool's result (or what went wrong) for the model.
    func call(_ function: Function, arguments: String) async -> (text: String, isError: Bool) {
        let args = arguments.trimmingCharacters(in: .whitespaces).isEmpty ? .object([:]) : JSONValue.parse(arguments)
        guard let args else { return ("The arguments are not valid JSON: \(arguments)", true) }
        switch function.target {
        case .registry(let tool):
            do { return (try registry(tool, args), false) }
            catch { return (error.localizedDescription, true) }
        case .app, .search:
            return ("This tool runs in the chat controller.", true)
        case .server(let id, let tool):
            guard let transport = transports[id] else { return ("The MCP server of this tool is not connected.", true) }
            do {
                let result = try await transport.request("tools/call", params: .object(["name": .string(tool), "arguments": args]))
                let isError: Bool = { if case .bool(true)? = result["isError"] { return true }; return false }()
                var parts: [String] = []
                for item in result["content"]?.array ?? [] {
                    switch item["type"]?.string {
                    case "text": parts.append(item["text"]?.string ?? "")
                    case "resource": parts.append(item["resource"]?["text"]?.string ?? item["resource"]?.jsonString ?? "")
                    case let type?: parts.append("[\(type) content]")
                    case nil: parts.append(item.jsonString)
                    }
                }
                if parts.isEmpty, let structured = result["structuredContent"] { parts.append(structured.jsonString) }
                return (parts.joined(separator: "\n"), isError)
            } catch is CancellationError {
                return ("Cancelled.", true)
            } catch {
                return ("The tool failed: \(error.localizedDescription)", true)
            }
        }
    }

    /// The name a server has in the registry, from the prefix of a function name.
    func displayName(ofSlug slug: String) -> String {
        if slug == Self.registryPrefix { return "GlassChat" }
        return servers.first { Self.slug($0.name, limit: 20) == slug }?.name ?? slug
    }

    /// How many tools the model is offered (the search included).
    func activeToolCount(disabled: Set<String>) -> Int {
        functions(disabled: disabled).count
    }

    /// Letters, digits, `_` and `-` only: what function names may hold.
    static func slug(_ text: String, limit: Int) -> String {
        let allowed = text.unicodeScalars.map { (CharacterSet.alphanumerics.contains($0) && $0.isASCII) || $0 == "_" || $0 == "-" ? Character($0) : "_" }
        let slug = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return String((slug.isEmpty ? "mcp" : slug).prefix(max(limit, 1)))
    }
}

private func withTimeout<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw MCPError(message: "No answer in \(Int(seconds)) s")
        }
        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}
