#if DEBUG
import AppKit

extension SelfTests {
    /// Runs async main-actor work by turning the run loop (self-tests run before the app's own loop).
    private static func wait<T>(_ seconds: TimeInterval, _ work: @escaping @MainActor () async -> T) -> T? {
        var result: T?
        Task { @MainActor in result = await work() }
        let deadline = Date.now.addingTimeInterval(seconds)
        while result == nil, Date.now < deadline { RunLoop.main.run(until: Date.now.addingTimeInterval(0.05)) }
        return result
    }

    static func sandbox() {
        // The rules that keep a page off the network compile (WebKit rejects "a|b" in a filter).
        let compiled = wait(10) { await VisualSandbox.compiledRules() != nil }
        expect(compiled == true, "the network rules compile")
        let page = VisualPage.html(body: "<p>Hi</p>", libraries: [])
        let policy = page.range(of: "Content-Security-Policy")
        expect(policy != nil && page.contains("connect-src 'none'"), "the page's own policy forbids connections")
        expect(policy.map { p in page.range(of: "<script").map { p.lowerBound < $0.lowerBound } ?? true } == true,
               "the policy comes before any script")
        expect(page.contains("document.body.getBoundingClientRect()"), "the height is the body's, not the viewport's")

        // A page that reaches the network, or never finishes, is reported to the model.
        let reached = wait(15) {
            await VisualSandbox.check(html: """
            <script>
            try { const x = new XMLHttpRequest(); x.open('GET', 'https://httpbin.org/get', false); x.send();
                  if (x.status > 0) throw new Error('network reached ' + x.status) } catch (e) { if (String(e).includes('reached')) throw e }
            </script>
            """, libraries: [])
        }
        expect(reached.map { !$0.contains { $0.contains("network reached") } } == true, "the network is blocked")
        let looping = wait(10) { await VisualSandbox.check(html: "<script>while (true) {}</script>", libraries: [], timeout: 1) }
        expect(looping?.contains { $0.contains("did not finish") } == true, "a page that never finishes is an error")

        // What a call draws: only a page that was shown.
        var call = ToolCall(id: "v1", name: "glasschat__app_visualize", arguments: #"{"html": "<p>Hi</p>"}"#)
        expect(Visualization(call) == nil, "a call that has not run is not drawn")
        call.result = "Unknown tool glasschat__app_visualize."
        call.isError = true
        expect(Visualization(call) == nil, "a call that failed is not drawn")
        call.result = "Shown."
        call.isError = false
        expect(Visualization(call)?.id == "v1", "a shown page is drawn")

        // Package names from the model are checked before they go into a URL or a folder.
        expect(VisualLibraries.isValidPackage("d3") && VisualLibraries.isValidPackage("@observablehq/plot")
               && VisualLibraries.isValidPackage("chart.js"), "npm names")
        expect(!VisualLibraries.isValidPackage("chart js") && !VisualLibraries.isValidPackage("..")
               && !VisualLibraries.isValidPackage("../x") && !VisualLibraries.isValidPackage(""), "not npm names")

        // A gesture that starts without movement is decided by its first movement.
        expect(VisualScroll.decision(deltaX: 0, deltaY: 0, scrollY: 100, contentHeight: 900, frameHeight: 640) == nil,
               "no movement yet: undecided")
        expect(VisualScroll.decision(deltaX: 0, deltaY: -3, scrollY: 100, contentHeight: 900, frameHeight: 640) == false,
               "then the page scrolls")

        // Two messages with one id (a damaged chats.json) do not crash the chat.
        let message = Message(role: .user, content: "Hi")
        expect(ChatView.index([message, message]).count == 1, "duplicate ids are kept once")
    }
}
#endif
