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
    static func verdict(mode: ConfirmMode, safeProbability: Double?, allowedInChat: Bool) -> Verdict {
        if allowedInChat { return .run }
        switch mode {
        case .never: return .run
        case .always: return .ask(dangerous: false)
        case .auto:
            guard let safe = safeProbability, safe >= 0.5 else { return .ask(dangerous: true) }
            return .run
        }
    }
}

/// An action waiting for the user's word.
struct PendingAction: Sendable {
    let tool: AppTool
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

    private(set) var pending: [Chat.ID: Pending] = [:]
    private var waiting: [Chat.ID: ResumeOnce<ApprovalDecision>] = [:]
    /// "chat|tool" allowed until the app quits.
    private var allowed: Set<String> = []

    private init() {}

    func isAllowed(_ tool: AppTool, in chat: Chat.ID) -> Bool {
        allowed.contains("\(chat)|\(tool.rawValue)")
    }

    /// True when the user allows it; false when they deny it, or the answer is stopped.
    func approve(_ action: PendingAction, callID: String, in chat: Chat.ID) async -> Bool {
        dismiss(in: chat)
        let once = ResumeOnce<ApprovalDecision>()
        pending[chat] = Pending(callID: callID, action: action)
        waiting[chat] = once
        let decision = await withTaskCancellationHandler {
            await withCheckedContinuation { once.set($0) }
        } onCancel: {
            once.resume(.deny)
            Task { @MainActor in ApprovalCenter.shared.dismiss(in: chat) }
        }
        if decision == .allowInChat { allowed.insert("\(chat)|\(action.tool.rawValue)") }
        return decision != .deny
    }

    func answer(_ decision: ApprovalDecision, in chat: Chat.ID) {
        pending[chat] = nil
        waiting.removeValue(forKey: chat)?.resume(decision)
    }

    func dismiss(in chat: Chat.ID) {
        answer(.deny, in: chat)
    }
}

/// The check before a file or terminal tool runs.
enum ActionGate {
    /// Returns when the action may run; throws when the user denied it.
    @MainActor
    static func check(_ action: PendingAction, callID: String, chat: Chat.ID) async throws {
        let mode = AppSettings.shared.confirmActions
        let center = ApprovalCenter.shared
        let allowed = center.isAllowed(action.tool, in: chat)
        var safe: Double?
        if mode == .auto, !allowed { safe = await safeProbability(action) }
        switch ApprovalPolicy.verdict(mode: mode, safeProbability: safe, allowedInChat: allowed) {
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
        let state = "An assistant on the user's Mac wants to do this (\(action.tool.rawValue)): \(action.summary)\n\(action.detail.prefix(2000))"
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
