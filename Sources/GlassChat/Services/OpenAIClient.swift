import Foundation

/// What a streamed answer yields.
enum StreamEvent: Sendable {
    case text(String)
    /// A piece of a tool call: the first piece of an index has its id and name, all add to the arguments.
    case toolCall(index: Int, id: String?, name: String?, arguments: String)
    case finish(reason: String?)
}

struct APIError: LocalizedError, Sendable {
    let status: Int?
    let message: String
    let url: URL?

    var errorDescription: String? {
        var text = status.map { "HTTP \($0): \(message)" } ?? message
        if status == 404, let url { text += " (\(url.absoluteString))" }
        return text
    }
}

/// A client of an OpenAI-compatible API (Chat Completions).
struct OpenAIClient: Sendable {
    let baseURL: URL
    let token: String

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 600
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func listModels() async throws -> [String] {
        let request = request("models")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, body: data, url: request.url)
        struct List: Decodable { struct Item: Decodable { let id: String }; let data: [Item] }
        let list = try JSONDecoder().decode(List.self, from: data)
        return list.data.map(\.id).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Streams an answer. `messages` are Chat Completions messages (content may be a list of parts),
    /// `tools` are function definitions; both go to the server as they are.
    func streamChat(model: String, messages: [JSONValue], tools: [JSONValue]) -> AsyncThrowingStream<StreamEvent, Error> {
        var request = request("chat/completions", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: JSONValue] = [
            "model": .string(model), "stream": .bool(true), "messages": .array(messages),
        ]
        if !tools.isEmpty { body["tools"] = .array(tools) }
        request.httpBody = try? JSONEncoder().encode(JSONValue.object(body))

        let sent = request
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: sent)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        try Self.check(response, body: body, url: sent.url)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        for event in Self.events(payload) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func events(_ payload: String) -> [StreamEvent] {
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable {
                    struct Call: Decodable {
                        struct Function: Decodable { let name: String?; let arguments: String? }
                        let index: Int?
                        let id: String?
                        let function: Function?
                    }
                    let content: String?
                    let tool_calls: [Call]?
                }
                let delta: Delta?
                let finish_reason: String?
            }
            let choices: [Choice]?
        }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)),
              let choice = chunk.choices?.first else { return [] }
        var events: [StreamEvent] = []
        if let text = choice.delta?.content, !text.isEmpty { events.append(.text(text)) }
        for (n, call) in (choice.delta?.tool_calls ?? []).enumerated() {
            events.append(.toolCall(index: call.index ?? n, id: call.id, name: call.function?.name,
                                    arguments: call.function?.arguments ?? ""))
        }
        if let reason = choice.finish_reason { events.append(.finish(reason: reason)) }
        return events
    }

    private struct ErrorBody: Decodable {
        struct Inner: Decodable { let message: String? }
        let error: Inner?
    }

    private static func check(_ response: URLResponse, body: Data, url: URL?) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error?.message
            ?? String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300).description
            ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        throw APIError(status: http.statusCode, message: message.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: http.statusCode) : message, url: url)
    }
}
