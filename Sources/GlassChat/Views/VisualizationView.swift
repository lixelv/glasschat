import SwiftUI
import WebKit

/// An `app_visualize` call's page, as the chat and the notch draw it.
struct Visualization: Equatable {
    let html: String
    let libraries: [String]
    let height: Double?

    /// Nil for other calls, and while the arguments are still being written.
    init?(_ call: ToolCall) {
        guard call.name == MCPManager.registryPrefix + "__" + AppTool.visualize.rawValue,
              let args = JSONValue.parse(call.arguments), let html = args["html"]?.string, !html.isEmpty else { return nil }
        self.html = html
        libraries = args["libraries"]?.array?.compactMap(\.string) ?? []
        height = args["height"]?.double
    }
}

/// What `app_visualize` drew: its page in the sandbox, as tall as its content (or the height asked for), at most
/// `maxHeight`; taller pages scroll inside.
struct VisualizationView: View {
    let html: String
    let libraries: [String]
    let height: Double?
    let maxHeight: CGFloat
    var dark = false

    init(_ visualization: Visualization, maxHeight: CGFloat, dark: Bool = false) {
        html = visualization.html
        libraries = visualization.libraries
        height = visualization.height
        self.maxHeight = maxHeight
        self.dark = dark
    }

    @State private var contentHeight: CGFloat = 60

    var body: some View {
        let wanted = height.map { CGFloat($0) } ?? contentHeight
        VisualWebView(html: html, libraries: libraries, dark: dark, contentHeight: $contentHeight)
            .frame(height: min(max(wanted, 24), maxHeight))
            .accessibilityLabel("Visualization")
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
                let configuration = await VisualSandbox.configuration(messages: self)
                guard let container, shown == key else { return }
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
    private var passing = false

    override func scrollWheel(with event: NSEvent) {
        let starts = event.phase.contains(.began) || (event.phase.isEmpty && event.momentumPhase.isEmpty)
        if starts {
            let state = scrollState()
            passing = VisualScroll.passesOn(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, scrollY: state.y,
                                            contentHeight: state.height, frameHeight: bounds.height)
        }
        if passing { nextResponder?.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
}
