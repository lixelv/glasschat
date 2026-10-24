import Foundation
import Observation

/// When `app_write`, `app_edit` and `app_bash` ask the user first.
enum ConfirmMode: String, CaseIterable, Sendable {
    /// The decision model judges the action; what it does not call safe is asked.
    case auto
    case always
    case never

    static let `default` = ConfirmMode.auto

    var title: String {
        switch self {
        case .auto: "Auto (the decision model judges)"
        case .always: "Always ask"
        case .never: "Never ask"
        }
    }
}

enum ApprovalPolicy {
    enum Verdict: Equatable { case run, ask(dangerous: Bool) }

    /// `safeProbability`: how sure the decision model is the action is harmless (nil: no answer).
    /// `judgedWhole`: the decision model saw all of the action (a longer one could hide its danger past the cut).
    static func verdict(mode: ConfirmMode, safeProbability: Double?, allowedInChat: Bool, judgedWhole: Bool = true) -> Verdict {
        if allowedInChat { return .run }
        switch mode {
        case .never: return .run
        case .always: return .ask(dangerous: false)
        case .auto:
            guard judgedWhole, let safe = safeProbability, safe >= 0.5 else { return .ask(dangerous: true) }
            return .run
        }
    }
}

/// An action waiting for the user's word.
struct PendingAction: Sendable {
    /// The tool's name ("app_bash", "_mcp_registry_add").
    let tool: String
    /// "Run a command", "Write /path".
    let summary: String
    /// The command, or the text going in.
    let detail: String
    var dangerous: Bool
}

enum ApprovalDecision: Sendable { case allow, allowInChat, deny }

/// Asks the user about an action and waits; the card (chat or notch) answers.
@Observable
@MainActor
final class ApprovalCenter {
    static let shared = ApprovalCenter()

    struct Pending: Sendable {
        let callID: String
        let action: PendingAction
    }

    /// Actions waiting in each chat, in order: the card shows the first (parallel calls wait their turn).
    private var queues: [Chat.ID: [Entry]] = [:]
    private struct Entry {
        let id = UUID()
        let pending: Pending
        let once: ResumeOnce<ApprovalDecision>
    }

    /// The action the card asks about, per chat.
    var pending: [Chat.ID: Pending] { queues.compactMapValues { $0.first?.pending } }
    /// "chat|tool" allowed until the app quits.
    private var allowed: Set<String> = []

    private init() {}

    func isAllowed(_ tool: String, in chat: Chat.ID) -> Bool {
        allowed.contains("\(chat)|\(tool)")
    }

    /// True when the user allows it; false when they deny it, or the answer is stopped.
    func approve(_ action: PendingAction, callID: String, in chat: Chat.ID) async -> Bool {
        let entry = Entry(pending: Pending(callID: callID, action: action), once: ResumeOnce<ApprovalDecision>())
        queues[chat, default: []].append(entry)
        let decision = await withTaskCancellationHandler {
            await withCheckedContinuation { entry.once.set($0) }
        } onCancel: {
            entry.once.resume(.deny)
            Task { @MainActor in ApprovalCenter.shared.remove(entry.id, in: chat) }
        }
        remove(entry.id, in: chat)
        if decision == .allowInChat { allowed.insert("\(chat)|\(action.tool)") }
        return decision != .deny
    }

    /// Answers the action the card shows.
    func answer(_ decision: ApprovalDecision, in chat: Chat.ID) {
        guard let first = queues[chat]?.first else { return }
        first.once.resume(decision)
        remove(first.id, in: chat)
    }

    /// Denies everything waiting in the chat (Stop, the chat deleted).
    func dismiss(in chat: Chat.ID) {
        for entry in queues.removeValue(forKey: chat) ?? [] { entry.once.resume(.deny) }
    }

    private func remove(_ id: UUID, in chat: Chat.ID) {
        queues[chat]?.removeAll { $0.id == id }
        if queues[chat]?.isEmpty == true { queues[chat] = nil }
    }
}

/// The check before a file or terminal tool runs.
enum ActionGate {
    /// What the decision model is shown of an action; anything longer is asked.
    static let judgedLength = 2000

    /// Returns when the action may run; throws when the user denied it.
    @MainActor
    static func check(_ action: PendingAction, callID: String, chat: Chat.ID) async throws {
        let mode = AppSettings.shared.confirmActions
        let center = ApprovalCenter.shared
        let allowed = center.isAllowed(action.tool, in: chat)
        let whole = action.detail.count <= ActionGate.judgedLength
        var safe: Double?
        if mode == .auto, !allowed, whole { safe = await safeProbability(action) }
        switch ApprovalPolicy.verdict(mode: mode, safeProbability: safe, allowedInChat: allowed, judgedWhole: whole) {
        case .run:
            return
        case .ask(let dangerous):
            var asked = action
            asked.dangerous = dangerous
            guard await center.approve(asked, callID: callID, in: chat) else {
                throw MCPError(message: "The user denied this action.")
            }
        }
    }

    /// The decision model's probability that the action is harmless; nil without a decision model or an answer.
    @MainActor
    private static func safeProbability(_ action: PendingAction) async -> Double? {
        guard let endpoint = AppSettings.shared.endpoint(.decision) else { return nil }
        let state = "An assistant on the user's Mac wants to do this (\(action.tool)): \(action.summary)\n\(action.detail)"
        let options = [
            "safe": "Harmless: reads, lists, builds or edits the user's own project files in an ordinary way; nothing is lost, sent away or changed in the system.",
            "dangerous": "Can destroy or overwrite data, delete files, send data or secrets elsewhere, install or run downloaded code, change system settings, or use sudo.",
        ]
        let probabilities = try? await Decisions.choose(state: state, instructions: "Is this action safe to run without asking the user?",
                                                        options: options, endpoint: endpoint)
        return probabilities?["safe"]
    }
}

/// The decision model (`/alpha/decisions`, e.g. Jev): which option fits, as probabilities.
enum Decisions {
    static func choose(state: String, instructions: String, options: [String: String], endpoint: ModelEndpoint) async throws -> [String: Double] {
        var root = endpoint.url.absoluteString
        if root.hasSuffix("/v1") { root.removeLast(3) }
        guard let url = URL(string: root + "/alpha/decisions") else { throw MCPError(message: "Bad decision URL") }
        let body: JSONValue = .object([
            "model": .string(endpoint.model),
            "state": .string(state),
            "questions": .object([
                "choice": .object([
                    "type": .string("choice"),
                    "instructions": .string(instructions),
                    "criteria": .object(options.mapValues { .string(String($0.prefix(400))) }),
                ]),
            ]),
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        guard (200..<300).contains(status), let answer = json?["answers"]?["choice"] else {
            let message = json?["error"]?["message"]?.string ?? json?["error"]?.string
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw MCPError(message: "The decision model \(endpoint.model) answered \(status): \(message)")
        }
        var result: [String: Double] = [:]
        if case .object(let probabilities)? = answer["probabilities"] {
            for (name, value) in probabilities where options[name] != nil {
                if case .number(let p) = value { result[name] = p }
            }
        }
        if result.isEmpty, let choice = answer["choice"]?.string, options[choice] != nil { result[choice] = 1 }
        return result
    }
}

/// The registry tools that start a program (an MCP server's command) count as running a command.
enum RegistryGate {
    /// The action to confirm before `name` runs with `args`; nil when it starts nothing. `existing`: the entry
    /// an enable switches on.
    static func action(for name: String, args: JSONValue, existing: JSONValue? = nil) -> PendingAction? {
        let config: JSONValue?
        switch name {
        case "_mcp_registry_add", "_mcp_registry_update": config = args["config"]
        case "_app_enable_mcp": config = existing
        default: return nil
        }
        guard let command = config?["command"]?.string else { return nil }
        let arguments = (config?["args"]?.array ?? []).compactMap(\.string)
        let server = args["name"]?.string ?? "?"
        return PendingAction(tool: name, summary: "Start the MCP server \"\(server)\"",
                             detail: ([command] + arguments).joined(separator: " "), dangerous: false)
    }
}
