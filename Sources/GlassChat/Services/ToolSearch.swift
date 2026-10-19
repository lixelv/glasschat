import Foundation

/// `search_tools`: finds tools by what they do, among all of them (switched off ones included), so the
/// switched-off ones need not be sent with every request. A decision model (e.g. Jev, through `/alpha/decisions`)
/// ranks them in `choice` mode, the options being the function names; without one, words are matched.
/// The best `decisionTopN` are offered to the model for the rest of the answer.
enum ToolSearch {
    static let description = "Find tools by what they should do (e.g. \"show a notification\", \"read a file\"). Tools that are switched off can only be used after they are found here; the found ones are offered from your next step on. Search when no tool you have fits."

    static let parameters: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "query": .object(["type": .string("string"), "description": .string("What the tool should do")]),
        ]),
        "required": .array([.string("query")]),
    ])

    struct Hit: Sendable {
        let name: String
        let probability: Double?
    }

    /// The best tools for `query` among `candidates` (name → summary), best first.
    @MainActor
    static func search(_ query: String, among candidates: [String: String]) async throws -> [Hit] {
        let settings = AppSettings.shared
        let limit = max(1, settings.decisionTopN)
        let model = settings.decisionModel.trimmingCharacters(in: .whitespaces)
        guard !candidates.isEmpty else { return [] }
        if model.isEmpty { return Array(wordSearch(query, candidates).prefix(limit)) }
        guard let connection = settings.decisionConnection else {
            throw MCPError(message: "The decision model's base URL is not valid (Settings → Connection).")
        }
        let ranked = try await decide(query, candidates, model: model, base: connection.url, token: connection.token)
        return Array(ranked.prefix(limit))
    }

    /// Asks the decision model which option fits; options are ranked by their probabilities.
    private static func decide(_ query: String, _ candidates: [String: String], model: String, base: URL, token: String) async throws -> [Hit] {
        var root = base.absoluteString
        if root.hasSuffix("/v1") { root.removeLast(3) }
        guard let url = URL(string: root + "/alpha/decisions") else { throw MCPError(message: "Bad decision URL") }
        let criteria = candidates.mapValues { JSONValue.string(String($0.prefix(400))) }
        let body: JSONValue = .object([
            "model": .string(model),
            "state": .string("An assistant needs a tool for this: \(query)"),
            "questions": .object([
                "tool": .object([
                    "type": .string("choice"),
                    "instructions": .string("Which tool does the assistant need for the request? Each option is a tool, described by what it does."),
                    "criteria": .object(criteria),
                ]),
            ]),
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        guard (200..<300).contains(status), let answer = json?["answers"]?["tool"] else {
            let message = json?["error"]?["message"]?.string ?? json?["error"]?.string
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw MCPError(message: "The decision model \(model) answered \(status): \(message)")
        }
        var hits: [Hit] = []
        if case .object(let probabilities)? = answer["probabilities"] {
            for (name, value) in probabilities where candidates[name] != nil {
                if case .number(let p) = value { hits.append(Hit(name: name, probability: p)) }
            }
            hits.sort { ($0.probability ?? 0) > ($1.probability ?? 0) }
        }
        if let choice = answer["choice"]?.string, candidates[choice] != nil, !hits.contains(where: { $0.name == choice }) {
            hits.insert(Hit(name: choice, probability: nil), at: 0)
        }
        return hits
    }

    /// Without a decision model: tools ranked by how many words of the query their name and description share.
    static func wordSearch(_ query: String, _ candidates: [String: String]) -> [Hit] {
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        }
        let wanted = words(query)
        return candidates
            .map { name, summary -> (String, Double) in
                let have = words(name + " " + summary)
                let score = wanted.reduce(0.0) { total, word in
                    total + (have.contains(word) ? 1 : have.contains { $0.hasPrefix(word.prefix(4)) } ? 0.5 : 0)
                }
                return (name, score)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { Hit(name: $0.0, probability: nil) }
    }
}
