import Foundation
import Observation

/// The MCP servers of Settings: kept in mcp.json, connected while enabled, and their tools offered to the model.
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
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([MCPServer].self, from: data) {
            servers = saved
        }
    }

    // MARK: Settings

    func add(_ server: MCPServer) {
        servers.append(server)
        changed()
    }

    func update(_ server: MCPServer) {
        guard let i = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[i] = server
        changed()
    }

    func remove(_ id: MCPServer.ID) {
        servers.removeAll { $0.id == id }
        changed()
    }

    func reconnect(_ id: MCPServer.ID) {
        Task { await disconnect(id); syncConnections() }
    }

    private func changed() {
        if let data = try? JSONEncoder().encode(servers) { try? data.write(to: Self.fileURL, options: .atomic) }
        syncConnections()
    }

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
        for id in Array(transports.keys) where !servers.contains(where: { $0.id == id }) {
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
                guard !server.command.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw MCPError(message: "No command")
                }
                let stdio = try StdioTransport(command: server.command, environment: server.environmentPairs)
                await stdio.start()
                transport = stdio
            case .http:
                guard let url = URL(string: server.url.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
                    throw MCPError(message: "The URL is not valid")
                }
                transport = HTTPTransport(url: url, headers: server.headerPairs)
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
        let definition: JSONValue
        let serverID: MCPServer.ID
        let tool: String
    }

    /// The tools of the connected servers not switched off in the chat, keyed by the function name the model sees.
    func functions(disabled: Set<MCPServer.ID>) -> [String: Function] {
        var result: [String: Function] = [:]
        for server in servers where server.enabled && !disabled.contains(server.id) && status[server.id] == .connected {
            let prefix = Self.slug(server.name, limit: 20)
            for tool in tools[server.id] ?? [] {
                var name = prefix + "__" + Self.slug(tool.name, limit: 60 - prefix.count)
                var n = 2
                while result[name] != nil { name = String(name.prefix(60)) + "\(n)"; n += 1 }
                let definition: JSONValue = .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(name),
                        "description": .string(tool.description.isEmpty ? "\(tool.name) (\(server.name))" : tool.description),
                        "parameters": tool.inputSchema,
                    ]),
                ])
                result[name] = Function(definition: definition, serverID: server.id, tool: tool.name)
            }
        }
        return result
    }

    /// Calls a tool; the text is the tool's result (or what went wrong) for the model.
    func call(_ function: Function, arguments: String) async -> (text: String, isError: Bool) {
        guard let transport = transports[function.serverID] else {
            return ("The MCP server of this tool is not connected.", true)
        }
        let args = arguments.trimmingCharacters(in: .whitespaces).isEmpty ? .object([:]) : JSONValue.parse(arguments)
        guard let args else { return ("The arguments are not valid JSON: \(arguments)", true) }
        do {
            let result = try await transport.request("tools/call", params: .object([
                "name": .string(function.tool), "arguments": args,
            ]))
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

    /// The name a server has in Settings, from the prefix of a function name.
    func displayName(ofSlug slug: String) -> String {
        servers.first { Self.slug($0.name, limit: 20) == slug }?.name ?? slug
    }

    func activeToolCount(disabled: Set<MCPServer.ID>) -> Int {
        servers.filter { $0.enabled && !disabled.contains($0.id) && status[$0.id] == .connected }
            .reduce(0) { $0 + (tools[$1.id]?.count ?? 0) }
    }

    /// Letters, digits, `_` and `-` only: what function names may hold.
    static func slug(_ text: String, limit: Int) -> String {
        let allowed = text.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-" ? Character($0) : "_" }
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
