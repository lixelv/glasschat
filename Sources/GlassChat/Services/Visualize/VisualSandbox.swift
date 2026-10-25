import AppKit
import WebKit

/// Where a visualization runs: a web view with no network, no files, no stored data and no navigation. Its own
/// scheme serves only the common style and the libraries' folders; the page talks to the app only through the
/// `height`, `error` and `ready` messages.
@MainActor
enum VisualSandbox {
    /// Every load is blocked but the app's own scheme, data:, blob: and about: (WebKit's filters have no "a|b").
    private static let rules = """
    [{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
     {"trigger": {"url-filter": "^glasschat-viz:"}, "action": {"type": "ignore-previous-rules"}},
     {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
     {"trigger": {"url-filter": "^blob:"}, "action": {"type": "ignore-previous-rules"}},
     {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}}]
    """
    private static var compiled: WKContentRuleList?

    /// The rules, compiled once; nil when WebKit refuses them (then no page is shown).
    static func compiledRules() async -> WKContentRuleList? {
        if compiled == nil {
            do {
                compiled = try await WKContentRuleListStore.default()
                    .compileContentRuleList(forIdentifier: "glasschat-visualize-2", encodedContentRuleList: rules)
            } catch {
                chatLog.error("visualize rules: \(error.localizedDescription, privacy: .public)")
            }
        }
        return compiled
    }

    /// A configuration for one page; `handler` gets its messages. Nil without the network rules: no page then.
    static func configuration(messages handler: WKScriptMessageHandler) async -> WKWebViewConfiguration? {
        guard let rules = await compiledRules() else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(SchemeHandler(), forURLScheme: VisualPage.scheme)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        for name in ["height", "scroll", "error", "ready"] {
            configuration.userContentController.add(WeakHandler(handler), name: name)
        }
        configuration.userContentController.add(rules)
        return configuration
    }

    /// Lets the page's first load through; links, redirects and scripts navigating away are stopped.
    final class Navigation: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            let ownPage = url.scheme == VisualPage.scheme || url.absoluteString == "about:blank"
            return ownPage && action.navigationType == .other ? .allow : .cancel
        }
    }

    // MARK: Files

    /// A file inside `folder`, or nil when the path leads out of it.
    nonisolated static func file(in folder: URL, path: String) -> URL? {
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { return nil }
        let url = parts.reduce(folder) { $0.appending(path: $1) }.standardizedFileURL
        let root = folder.standardizedFileURL.path
        return url.path.hasPrefix(root + "/") ? url : nil
    }

    nonisolated static func mimeType(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "js", "mjs": "text/javascript"
        case "css": "text/css"
        case "json", "map": "application/json"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "woff2": "font/woff2"
        case "woff": "font/woff"
        case "ttf": "font/ttf"
        default: "application/octet-stream"
        }
    }

    /// `glasschat-viz://style/<file>` from the app, `glasschat-viz://lib/<name>/<path>` from a library's folder.
    final class SchemeHandler: NSObject, WKURLSchemeHandler {
        func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
            guard let url = task.request.url, let data = Self.data(for: url) else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            task.didReceive(URLResponse(url: url, mimeType: VisualSandbox.mimeType(url.lastPathComponent),
                                        expectedContentLength: data.count, textEncodingName: "utf-8"))
            task.didReceive(data)
            task.didFinish()
        }

        func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

        private static func data(for url: URL) -> Data? {
            let parts = url.path.split(separator: "/").map(String.init)
            switch url.host {
            case "style":
                guard let style = Bundle.module.url(forResource: "Visualize", withExtension: nil),
                      let file = VisualSandbox.file(in: style, path: parts.joined(separator: "/")) else { return nil }
                return try? Data(contentsOf: file)
            case "lib":
                guard let name = parts.first, let folder = VisualLibraries.shared.directory(for: name),
                      let file = VisualSandbox.file(in: folder, path: parts.dropFirst().joined(separator: "/")) else { return nil }
                return try? Data(contentsOf: file)
            default:
                return nil
            }
        }
    }

    /// WebKit keeps its message handlers strongly: the view's coordinator is held weakly.
    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(_ target: WKScriptMessageHandler) { self.target = target }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(controller, didReceive: message)
        }
    }

    // MARK: Checking a page before the model is answered

    /// Renders the page out of sight and returns its errors; at most `timeout` seconds.
    static func check(html: String, libraries: [VisualLibraries.Entry], timeout: TimeInterval = 3) async -> [String] {
        let probe = Probe()
        guard let configuration = await configuration(messages: probe) else {
            return ["The page could not be shown: the sandbox's network rules did not load."]
        }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        let navigation = Navigation()
        webView.navigationDelegate = navigation
        // Off screen, but in a window: WebKit lays out and runs timers only there.
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 600, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderBack(nil)
        defer {
            webView.stopLoading()
            window.orderOut(nil)
            window.contentView = nil
        }
        webView.loadHTMLString(VisualPage.html(body: html, libraries: libraries), baseURL: URL(string: "\(VisualPage.scheme)://page/"))
        let deadline = Date.now.addingTimeInterval(timeout)
        while !probe.ready, Date.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard probe.ready || Task.isCancelled else {
            return probe.errors + [notFinished(timeout)]
        }
        return probe.errors
    }

    static func notFinished(_ seconds: TimeInterval) -> String {
        "The page did not finish loading in \(Int(seconds)) s (an endless loop?)."
    }

    private final class Probe: NSObject, WKScriptMessageHandler {
        var errors: [String] = []
        var ready = false
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "error": errors.append(String(describing: message.body))
            case "ready": ready = true
            default: break
            }
        }
    }
}
