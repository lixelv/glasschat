#if DEBUG
import Foundation

extension SelfTests {
    static func approval() {
        func v(_ mode: ConfirmMode, _ safe: Double?, chat: Bool = false) -> ApprovalPolicy.Verdict {
            ApprovalPolicy.verdict(mode: mode, safeProbability: safe, allowedInChat: chat)
        }
        expect(v(.never, nil) == .run, "never ask: run")
        expect(v(.always, 0.99) == .ask(dangerous: false), "always ask: ask")
        expect(v(.auto, 0.9) == .run, "auto, safe: run")
        expect(v(.auto, 0.3) == .ask(dangerous: true), "auto, dangerous: ask in red")
        expect(v(.auto, nil) == .ask(dangerous: true), "auto without a decision: ask in red")
        expect(v(.auto, 0.1, chat: true) == .run && v(.always, nil, chat: true) == .run, "allowed in this chat: run")
        expect(ConfirmMode.default == .auto, "auto by default")
    }
}
#endif
