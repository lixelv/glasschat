import Foundation

struct MCPError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

/// Carries JSON-RPC messages to one MCP server.
protocol MCPTransport: Sendable {
    /// Sends a request and returns its `result` (a JSON-RPC error is thrown).
    func request(_ method: String, params: JSONValue) async throws -> JSONValue
    func notify(_ method: String, params: JSONValue) async throws
    func close() async
}

enum JSONRPC {
    static func message(id: Int?, method: String, params: JSONValue) -> Data {
        var body: [String: JSONValue] = ["jsonrpc": .string("2.0"), "method": .string(method), "params": params]
        if let id { body["id"] = .number(Double(id)) }
        return (try? JSONEncoder().encode(JSONValue.object(body))) ?? Data()
    }

    static func result(of response: JSONValue) throws -> JSONValue {
        if let error = response["error"] {
            let text = error["message"]?.string ?? error.jsonString
            throw MCPError(message: text)
        }
        return response["result"] ?? .null
    }

    static func id(of message: JSONValue) -> Int? {
        if case .number(let n)? = message["id"] { return Int(n) }
        if let s = message["id"]?.string { return Int(s) }
        return nil
    }
}

// MARK: - stdio

/// A local server: a process speaking newline-delimited JSON-RPC on stdin/stdout.
/// It is started through a login shell, so `npx`, `uvx` and the rest of the user's PATH are found.
actor StdioTransport: MCPTransport {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var nextID = 1
    private var waiting: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var buffer = Data()
    private var stderrTail = ""
    private var exited = false

    init(command: String, environment: [String: String]) throws {
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec \(command)"]
        var env = ProcessInfo.processInfo.environment
        for (k, v) in environment { env[k] = v }
        process.environment = env
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
    }

    /// Starts reading; call once after init.
    func start() {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.received(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.receivedError(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { await self?.terminated() }
        }
    }

    private func received(_ data: Data) {
        if data.isEmpty { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let message = try? JSONDecoder().decode(JSONValue.self, from: line),
                  let id = JSONRPC.id(of: message), message["method"] == nil,
                  let continuation = waiting.removeValue(forKey: id) else { continue }
            do { continuation.resume(returning: try JSONRPC.result(of: message)) }
            catch { continuation.resume(throwing: error) }
        }
    }

    private func receivedError(_ data: Data) {
        stderrTail = String((stderrTail + String(decoding: data, as: UTF8.self)).suffix(800))
    }

    private func terminated() {
        exited = true
        let reason = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        let error = MCPError(message: "The server exited (code \(process.terminationStatus))" + (reason.isEmpty ? "" : ": \(reason)"))
        for continuation in waiting.values { continuation.resume(throwing: error) }
        waiting.removeAll()
    }

    func request(_ method: String, params: JSONValue) async throws -> JSONValue {
        if exited { throw MCPError(message: "The server is not running. \(stderrTail)") }
        let id = nextID
        nextID += 1
        let data = JSONRPC.message(id: id, method: method, params: params) + Data([0x0A])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting[id] = continuation
                do { try input.fileHandleForWriting.write(contentsOf: data) }
                catch { waiting.removeValue(forKey: id)?.resume(throwing: error) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: Int) {
        waiting.removeValue(forKey: id)?.resume(throwing: CancellationError())
        try? input.fileHandleForWriting.write(contentsOf: JSONRPC.message(
            id: nil, method: "notifications/cancelled", params: .object(["requestId": .number(Double(id))])) + Data([0x0A]))
    }

    func notify(_ method: String, params: JSONValue) async throws {
        try input.fileHandleForWriting.write(contentsOf: JSONRPC.message(id: nil, method: method, params: params) + Data([0x0A]))
    }

    func close() {
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }
}

// MARK: - Streamable HTTP

/// A remote server over Streamable HTTP: each message is a POST, answered with JSON or an SSE stream.
actor HTTPTransport: MCPTransport {
    private let url: URL
    private let headers: [String: String]
    private var sessionID: String?
    private var protocolVersion: String?
    private var nextID = 1

    init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }

    func setProtocolVersion(_ version: String) {
        protocolVersion = version
    }

    private func post(_ body: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if let protocolVersion { request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version") }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return request
    }

    func request(_ method: String, params: JSONValue) async throws -> JSONValue {
        let id = nextID
        nextID += 1
        let (bytes, response) = try await URLSession.shared.bytes(for: post(JSONRPC.message(id: id, method: method, params: params)))
        guard let http = response as? HTTPURLResponse else { throw MCPError(message: "No HTTP response") }
        if let session = http.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = session }
        if !(200..<300).contains(http.statusCode) {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw MCPError(message: "HTTP \(http.statusCode)" + (text.isEmpty ? "" : ": \(text.prefix(300))"))
        }
        let type = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if type.contains("text/event-stream") {
            // The answer is the event whose id is ours; others (progress, logs) are skipped.
            var data = ""
            for try await line in bytes.lines {
                if line.hasPrefix("data:") {
                    data += line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if let message = JSONValue.parse(data) {
                        data = ""
                        if JSONRPC.id(of: message) == id, message["method"] == nil { return try JSONRPC.result(of: message) }
                    }
                }
            }
            throw MCPError(message: "The server closed the stream without an answer")
        }
        var body = Data()
        for try await byte in bytes { body.append(byte) }
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: body) else {
            throw MCPError(message: "Not a JSON-RPC answer: \(String(decoding: body.prefix(200), as: UTF8.self))")
        }
        return try JSONRPC.result(of: message)
    }

    func notify(_ method: String, params: JSONValue) async throws {
        _ = try await URLSession.shared.data(for: post(JSONRPC.message(id: nil, method: method, params: params)))
    }

    func close() async {
        guard let sessionID else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        _ = try? await URLSession.shared.data(for: request)
    }
}
