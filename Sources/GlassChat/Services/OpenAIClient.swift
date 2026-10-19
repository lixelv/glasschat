import Foundation

struct ChatTurn: Codable, Sendable {
    let role: String
    let content: String
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

    func streamChat(model: String, messages: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        var request = request("chat/completions", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        struct Body: Encodable { let model: String; let stream: Bool; let messages: [ChatTurn] }
        request.httpBody = try? JSONEncoder().encode(Body(model: model, stream: true, messages: messages))

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
                        if let delta = Self.delta(payload), !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func delta(_ payload: String) -> String? {
        struct Chunk: Decodable {
            struct Choice: Decodable { struct Delta: Decodable { let content: String? }; let delta: Delta? }
            let choices: [Choice]?
            let error: ErrorBody.Inner?
        }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)) else { return nil }
        return chunk.choices?.first?.delta?.content
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
