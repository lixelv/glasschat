#if DEBUG
import Foundation

extension SelfTests {
    static func askUser() {
        func args(questions: Int, options: Int, text: String? = "Q") -> JSONValue {
            let opts = JSONValue.array((0..<options).map { .object(["label": .string("O\($0)")]) })
            return .object(["questions": .array((0..<questions).map { _ in
                var q: [String: JSONValue] = ["options": opts]
                if let text { q["question"] = .string(text) }
                return .object(q)
            })])
        }
        let ok = JSONValue.parse(#"{"questions":[{"question":"Format?","header":"Fmt","options":[{"label":"PDF","description":"print"},{"label":"MD"}],"multi_select":true}]}"#)!
        expect((try? AskUser.parse(ok))?.first?.options.count == 2 && (try? AskUser.parse(ok))?.first?.multiSelect == true, "parses")
        expect((try? AskUser.parse(args(questions: 1, options: 2, text: nil))) == nil, "question required")
        expect((try? AskUser.parse(args(questions: 1, options: 0))) == nil, "at least one option")
        expect((try? AskUser.parse(args(questions: 1, options: 7))) == nil, "at most six options")
        expect((try? AskUser.parse(args(questions: 5, options: 2))) == nil, "at most four questions")
        expect((try? AskUser.parse(args(questions: 4, options: 6)))?.count == 4, "limits are inclusive")

        let qs3 = (try? AskUser.parse(args(questions: 3, options: 2))) ?? []
        let r = JSONValue.parse(AskUser.result(qs3, [.one("PDF"), .skipped, .many(["a", "b"])]))
        let answers = r?["answers"]?.array ?? []
        expect(answers.count == 3 && answers[0]["answer"]?.string == "PDF" && answers[1]["answer"] == JSONValue.null
               && answers[2]["answer"]?.array?.count == 2 && answers[0]["question"]?.string == "Q", "result shape")

        var p = PendingQuestions(callID: "c", questions: qs3)
        p.answer(.one("PDF")); p.back(); expect(p.index == 0, "back")
        p.back(); expect(p.index == 0, "back at first stays")
        p.answer(.one("x")); p.answer(.skipped); p.answer(.one("y")); expect(p.isReviewing, "review after last")
        p.answer(.one("z")); expect(p.answers[2] == .one("y"), "no answers in review")
    }
}
#endif
