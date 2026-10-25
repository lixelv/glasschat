import Foundation

/// `search_tools` finds the hidden tools (not sent with every request), `search_all_tools` every tool, switched-off
/// ones included (`ToolCatalog`). A decision model (e.g. Jev, through `/alpha/decisions`) ranks them in `choice` mode,
/// the options being the function names; without one, words are matched.
/// The best `decisionTopN` are offered to the model for the rest of the answer.
enum ToolSearch {
    static let description = "Find a tool that is not in your list: rarely used tools are kept out of it (chats, models, MCP servers, notifications, alert windows, libraries, and servers the user set to on demand). Describe what it should do in English (e.g. \"show a notification\", \"switch model\"), or give its exact name. The found tools are offered from your next step on. If nothing fits, use search_all_tools."

    static let allDescription = "Search every tool, also the ones the user switched off. Only when search_tools found nothing that fits. Describe what it should do in English, or give its exact name; the found tools are offered from your next step on."

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
        let endpoint = settings.endpoint(.decision)
        guard !candidates.isEmpty else { return [] }
        // An exact function name (or the tool part of it) is found whatever ranks it.
        let wanted = query.trimmingCharacters(in: .whitespaces).lowercased()
        let exact = candidates.keys.filter { $0.lowercased() == wanted || $0.lowercased().hasSuffix("__" + wanted) }
        if !exact.isEmpty { return exact.sorted().map { Hit(name: $0, probability: nil) } }
        guard let endpoint else { return Array(wordSearch(query, candidates).prefix(limit)) }
        let ranked = try await decide(query, candidates, endpoint: endpoint)
        return Array(ranked.prefix(limit))
    }

    /// Asks the decision model which tool fits; tools are ranked by their probabilities.
    private static func decide(_ query: String, _ candidates: [String: String], endpoint: ModelEndpoint) async throws -> [Hit] {
        let probabilities = try await Decisions.choose(
            state: "An assistant needs a tool for this: \(query)",
            instructions: "Which tool does the assistant need for the request? Each option is a tool, described by what it does.",
            options: candidates, endpoint: endpoint)
        return probabilities.map { Hit(name: $0.key, probability: $0.value) }
            .sorted { ($0.probability ?? 0) > ($1.probability ?? 0) }
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
