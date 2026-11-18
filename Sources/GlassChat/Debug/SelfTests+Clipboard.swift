#if DEBUG
import Foundation

extension SelfTests {
    static func clipboard() {
        let read = "glasschat___app_read_clipboard", write = "glasschat___app_write_clipboard"
        // CLIP-3: the module.
        expect(AppModule.of(read) == .clipboard && AppModule.of(write) == .clipboard, "CLIP-3: both tools sit in the clipboard module")
        expect(AppModule.clipboard.title == "Clipboard", "CLIP-3: title")
        expect(AppModule.clipboard.summary == "Read and replace the clipboard's text", "CLIP-3: summary")
        expect(AppModule.switchable.contains(.clipboard), "CLIP-3: it can be switched off")
        expect(AppModule.clipboard.key == "__app__.clipboard", "CLIP-3: its switch key")

        let all = MCPManager.shared.allFunctions()
        expect(all[read] != nil && all[write] != nil, "CLIP-1/2: both tools exist")
        expect(all[read]?.group == AppModule.clipboard.key && all[write]?.group == AppModule.clipboard.key, "CLIP-3: grouped under the module switch")

        // CLIP-3: hidden tools.
        let offered = MCPManager.shared.functions(disabled: [])
        expect(offered[read] == nil && offered[write] == nil, "CLIP-3: hidden: not offered up front")
        expect(Set(ToolCatalog.candidates(all, scope: .hidden, disabled: [], onDemand: []).keys).isSuperset(of: [read, write]),
               "CLIP-3: search_tools finds them")
        expect(ToolCatalog.candidates(all, scope: .hidden, disabled: [AppModule.clipboard.key], onDemand: []).keys.contains(read) == false,
               "CLIP-3: not when the module is off")
        expect(ToolCatalog.offered(all, disabled: [], found: [read, write], onDemand: []).keys.contains(write),
               "CLIP-3: offered once found")

        // CLIP-1 / CLIP-2: the definitions.
        func text(_ name: String) -> String {
            ((try? JSONEncoder().encode(all[name]?.definition)).flatMap { String(data: $0, encoding: .utf8) } ?? "").lowercased()
        }
        func required(_ value: JSONValue?) -> [String]? {
            guard case .object(let dict)? = value else { return nil }
            if case .array(let items)? = dict["required"] { return items.compactMap { if case .string(let s) = $0 { s } else { nil } } }
            for inner in dict.values { if let found = required(inner) { return found } }
            return nil
        }
        expect(text(write).contains("\"text\""), "CLIP-2: write takes text")
        expect(required(all[write]?.definition) == ["text"], "CLIP-2: text is required")
        expect(required(all[read]?.definition)?.isEmpty ?? true, "CLIP-1: read takes no arguments")

        // CLIP-4: only when asked.
        expect(text(read).contains("only when the user") && text(write).contains("only when the user"), "CLIP-4: tool descriptions say only when the user asks")
        let prompt = AssistantPrompt.standard.lowercased()
        expect(prompt.contains("clipboard"), "CLIP-4: the prompt mentions the clipboard")
        expect(prompt.contains("only when the user") || prompt.contains("only if the user"), "CLIP-4: the prompt says only when the user asks")
        expect(AssistantPrompt.previous.contains { $0.contains("glasschat__app_visualize") && $0.contains("charts, diagrams and interactive pages") },
               "CLIP-4: the former standard prompt moved to previous")
        expect(AssistantPrompt.previous.allSatisfy { !$0.lowercased().contains("clipboard") }, "CLIP-4: no earlier prompt mentions it")
        expect(!AssistantPrompt.previous.contains(AssistantPrompt.standard), "CLIP-4: the new standard is not in previous")
        expect(AssistantPrompt.previous.allSatisfy { AssistantPrompt.stored($0) == AssistantPrompt.standard }, "CLIP-4: every former standard prompt is replaced by the new one")
    }
}
#endif
