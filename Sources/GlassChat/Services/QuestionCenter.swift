import Foundation
import Observation

struct AskOption: Sendable, Hashable {
    let label: String
    let description: String?
}

struct AskQuestion: Sendable, Hashable {
    let question: String
    let header: String?
    let options: [AskOption]
    let multiSelect: Bool
}

enum AskAnswer: Sendable, Hashable {
    case skipped, one(String), many([String])
}

/// `app_ask_user`: its arguments and its result for the model.
enum AskUser {
    static func parse(_ args: JSONValue) throws -> [AskQuestion] {
        guard let items = args["questions"]?.array, (1...4).contains(items.count) else {
            throw MCPError(message: "\"questions\" must hold one to four questions.")
        }
        return try items.map { item in
            guard let question = item["question"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty else {
                throw MCPError(message: "Every question needs a \"question\" text.")
            }
            let options = (item["options"]?.array ?? []).compactMap { option -> AskOption? in
                guard let label = option["label"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return nil }
                return AskOption(label: label, description: option["description"]?.string?.nilIfEmpty)
            }
            guard (1...6).contains(options.count) else {
                throw MCPError(message: "\"\(question)\" needs one to six options with a \"label\".")
            }
            let multi: Bool = { if case .bool(true)? = item["multi_select"] { return true }; return false }()
            return AskQuestion(question: question, header: item["header"]?.string?.nilIfEmpty, options: options, multiSelect: multi)
        }
    }

    /// `{"answers":[{"question":…,"answer":…}]}`: a skipped question answers null.
    static func result(_ questions: [AskQuestion], _ answers: [AskAnswer]) -> String {
        let items: [JSONValue] = zip(questions, answers).map { question, answer in
            let value: JSONValue = switch answer {
            case .skipped: .null
            case .one(let text): .string(text)
            case .many(let texts): .array(texts.map(JSONValue.string))
            }
            return .object(["question": .string(question.question), "answer": value])
        }
        return JSONValue.object(["answers": .array(items)]).jsonString
    }
}

/// Questions waiting for the user, answered one after the other, then confirmed.
struct PendingQuestions: Sendable {
    let callID: String
    let questions: [AskQuestion]
    private(set) var index = 0
    private(set) var answers: [AskAnswer]

    init(callID: String, questions: [AskQuestion]) {
        self.callID = callID
        self.questions = questions
        answers = questions.map { _ in .skipped }
    }

    /// All answered: the summary with Confirm.
    var isReviewing: Bool { index >= questions.count }

    mutating func answer(_ answer: AskAnswer) {
        guard !isReviewing else { return }
        answers[index] = answer
        index += 1
    }

    mutating func back() {
        index = max(index - 1, 0)
    }
}

/// The questions of `app_ask_user` waiting for the user, by chat: the card (window or notch) answers them.
@Observable
@MainActor
final class QuestionCenter {
    static let shared = QuestionCenter()

    private(set) var pending: [Chat.ID: PendingQuestions] = [:]
    private var waiting: [Chat.ID: ResumeOnce<[AskAnswer]?>] = [:]

    private init() {}

    /// The answers once confirmed; nil when the user cancelled or the answer was stopped.
    func ask(_ questions: [AskQuestion], callID: String, in chat: Chat.ID) async throws -> [AskAnswer]? {
        guard pending[chat] == nil else {
            throw MCPError(message: "Another question is waiting for the user; ask all questions in one call.")
        }
        let once = ResumeOnce<[AskAnswer]?>()
        pending[chat] = PendingQuestions(callID: callID, questions: questions)
        waiting[chat] = once
        return await withTaskCancellationHandler {
            await withCheckedContinuation { once.set($0) }
        } onCancel: {
            once.resume(nil)
            Task { @MainActor in QuestionCenter.shared.dismiss(in: chat) }
        }
    }

    func answer(_ answer: AskAnswer, in chat: Chat.ID) {
        pending[chat]?.answer(answer)
    }

    func back(in chat: Chat.ID) {
        pending[chat]?.back()
    }

    func confirm(in chat: Chat.ID) {
        guard let questions = pending[chat] else { return }
        close(chat, with: questions.answers)
    }

    func dismiss(in chat: Chat.ID) {
        close(chat, with: nil)
    }

    private func close(_ chat: Chat.ID, with answers: [AskAnswer]?) {
        pending[chat] = nil
        waiting.removeValue(forKey: chat)?.resume(answers)
    }
}
