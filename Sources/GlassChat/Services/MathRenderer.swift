import AppKit
import WebKit

/// Renders LaTeX with KaTeX (bundled, offline) in one hidden web view and snapshots it into images.
/// KaTeX covers what models write: \boxed, \operatorname, arrays, \underbrace, Cyrillic in \text...
@MainActor
final class MathRenderer: NSObject, WKNavigationDelegate {
    static let shared = MathRenderer()

    private let webView: WKWebView
    private let window: NSWindow
    private var ready: CheckedContinuation<Void, Never>?
    private var isReady = false
    private var cache: [String: Formula] = [:]

    /// A rendered formula and how far it reaches below the text baseline.
    struct Formula {
        let image: NSImage
        let depth: CGFloat
    }
    private var queue: Task<Void, Never>?

    private override init() {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1600, height: 600))
        webView.setValue(false, forKey: "drawsBackground")
        // Off screen, but in a window: WebKit paints only what is in one.
        window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1600, height: 600),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = webView
        window.orderBack(nil)
        super.init()
        webView.navigationDelegate = self
        if let page = Bundle.module.url(forResource: "render", withExtension: "html", subdirectory: "KaTeX") {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        } else {
            FileHandle.standardError.write(Data("KaTeX page not found in \(Bundle.module.bundlePath)\n".utf8))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("KaTeX page failed: \(error)\n".utf8))
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("KaTeX page failed to load: \(error)\n".utf8))
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        FileHandle.standardError.write(Data("KaTeX web process terminated\n".utf8))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            isReady = true
            ready?.resume()
            ready = nil
        }
    }

    /// An image of the formula in the given colour; nil when KaTeX cannot parse it.
    func image(tex: String, display: Bool, fontSize: CGFloat, dark: Bool) async -> Formula? {
        let key = "\(display)|\(fontSize)|\(dark)|\(tex)"
        if let cached = cache[key] { return cached }
        // One formula at a time: they share the page.
        let previous = queue
        let task = Task { @MainActor () -> Formula? in
            await previous?.value
            return await render(tex: tex, display: display, fontSize: fontSize, dark: dark)
        }
        queue = Task { _ = await task.value }
        let image = await task.value
        if let image { cache[key] = image }
        return image
    }

    private func render(tex: String, display: Bool, fontSize: CGFloat, dark: Bool) async -> Formula? {
        if !isReady { await withCheckedContinuation { ready = $0 } }
        let color = dark ? "rgba(255,255,255,0.88)" : "rgba(0,0,0,0.88)"
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(
                "return render(tex, display, color, size)",
                arguments: ["tex": tex, "display": display, "color": color, "size": fontSize],
                contentWorld: .page)
        } catch {
            FileHandle.standardError.write(Data("KaTeX call failed: \(error)\n".utf8))
            return nil
        }
        guard let info = result as? [String: Any], info["error"] == nil,
              let width = (info["width"] as? NSNumber)?.doubleValue,
              let height = (info["height"] as? NSNumber)?.doubleValue, width > 0, height > 0 else {
            FileHandle.standardError.write(Data("KaTeX refused \(tex): \(String(describing: result))\n".utf8))
            return nil
        }
        let depth = (info["depth"] as? NSNumber)?.doubleValue ?? 0
        // A PDF, not a snapshot: a snapshot waits for a screen update an off-screen window never gets,
        // and the vector image stays sharp at any scale.
        let config = WKPDFConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: min(width, 1600), height: min(height, 600))
        do {
            let data = try await webView.pdf(configuration: config)
            guard let image = NSImage(data: data) else { return nil }
            return Formula(image: image, depth: depth)
        } catch {
            FileHandle.standardError.write(Data("KaTeX PDF failed: \(error)\n".utf8))
            return nil
        }
    }
}
