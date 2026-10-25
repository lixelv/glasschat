import SwiftUI
import WebKit

/// An `app_visualize` call's page, as the chat and the notch draw it.
struct Visualization: Equatable {
    let id: String
    let html: String
    let libraries: [String]
    let height: Double?

    /// Nil for other calls, and for calls that were not shown (still running, failed, stopped, refused).
    init?(_ call: ToolCall) {
        guard call.name == MCPManager.registryPrefix + "__" + AppTool.visualize.rawValue,
              !call.isError, call.result?.hasPrefix("Shown") == true,
              let args = JSONValue.parse(call.arguments), let html = args["html"]?.string, !html.isEmpty else { return nil }
        id = call.id
        self.html = html
        libraries = args["libraries"]?.array?.compactMap(\.string) ?? []
        height = args["height"]?.double
    }
}

/// What `app_visualize` drew: its page in the sandbox, as tall as its content (at least the height asked for),
/// at most `maxHeight`; taller pages scroll inside.
struct VisualizationView: View {
    let html: String
    let libraries: [String]
    let height: Double?
    let maxHeight: CGFloat
    var dark = false

    init(_ visualization: Visualization, maxHeight: CGFloat, dark: Bool = false) {
        id = visualization.id
        _contentHeight = State(initialValue: Self.heights[visualization.id] ?? 60)
        html = visualization.html
        libraries = visualization.libraries
        height = visualization.height
        self.maxHeight = maxHeight
        self.dark = dark
    }

    @State private var contentHeight: CGFloat
    private let id: String

    /// The last height of each page: a row made again (scrolled back, moved out of the last messages) starts there
    /// instead of jumping.
    private static var heights: [String: CGFloat] = [:]

    var body: some View {
        let wanted = max(height.map { CGFloat($0) } ?? 0, contentHeight)
        VisualWebView(html: html, libraries: libraries, dark: dark, contentHeight: $contentHeight)
            .frame(height: min(max(wanted, 24), maxHeight))
            .accessibilityLabel("Visualization")
            .onChange(of: contentHeight) { _, height in Self.heights[id] = height }
    }
}

private struct VisualWebView: NSViewRepresentable {
    let html: String
    let libraries: [String]
    let dark: Bool
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $contentHeight) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let coordinator = context.coordinator
        coordinator.container = container
        coordinator.show(html: html, libraries: libraries, dark: dark)
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.height = $contentHeight
        context.coordinator.show(html: html, libraries: libraries, dark: dark)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        weak var container: NSView?
        /// Where the page is scrolled to and how tall it is, for the wheel.
        private var scrollY: CGFloat = 0
        private var pageHeight: CGFloat = 0
        private var webView: WKWebView?
        private var shown: String?
        private let navigation = VisualSandbox.Navigation()

        init(height: Binding<CGFloat>) { self.height = height }

        func show(html: String, libraries: [String], dark: Bool) {
            let key = html + "\u{0}" + libraries.joined(separator: ",")
            guard shown != key else { return }
            shown = key
            Task {
                guard let configuration = await VisualSandbox.configuration(messages: self),
                      let container, shown == key else { return }
                webView?.removeFromSuperview()
                let view = PassingWebView(frame: container.bounds, configuration: configuration)
                view.scrollState = { [weak self] in (self?.scrollY ?? 0, self?.pageHeight ?? 0) }
                view.autoresizingMask = [.width, .height]
                view.setValue(false, forKey: "drawsBackground")
                if dark { view.appearance = NSAppearance(named: .darkAqua) }
                view.navigationDelegate = navigation
                container.addSubview(view)
                webView = view
                let entries = libraries.compactMap { VisualLibraries.shared.entry($0) }
                view.loadHTMLString(VisualPage.html(body: html, libraries: entries),
                                    baseURL: URL(string: "\(VisualPage.scheme)://page/"))
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            let value = (message.body as? NSNumber).map { CGFloat($0.doubleValue) }
            switch message.name {
            case "height":
                guard let value, value > 0 else { return }
                pageHeight = value
                height.wrappedValue = value
            case "scroll":
                scrollY = value ?? 0
            default:
                break
            }
        }
    }
}

/// Hands the wheel to the chat when the page cannot scroll that way, for the whole gesture
/// (a page in the chat must not trap the scrolling).
private final class PassingWebView: WKWebView {
    var scrollState: () -> (y: CGFloat, height: CGFloat) = { (0, 0) }
    /// Who scrolls in this gesture; nil until it moves (a trackpad's first event often has no movement).
    private var passing: Bool?

    override func scrollWheel(with event: NSEvent) {
        let starts = event.phase.contains(.began) || (event.phase.isEmpty && event.momentumPhase.isEmpty)
        if starts { passing = nil }
        if passing == nil {
            let state = scrollState()
            passing = VisualScroll.decision(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, scrollY: state.y,
                                            contentHeight: state.height, frameHeight: bounds.height)
        }
        if passing == true { nextResponder?.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
}
