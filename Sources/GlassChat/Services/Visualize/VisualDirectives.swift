import Foundation

/// What the model is told about `app_visualize`: when to draw, how the page looks, and which libraries it has.
enum VisualDirectives {
    static func description(libraries: [VisualLibraries.Entry]) -> String {
        let list = libraries.map { entry in
            "\(entry.name) (global \(entry.global ?? "none")): \(entry.purpose)"
        }
        return """
        Draw a visualization in the chat and the notch: the body of an HTML page, with <style> and <script>. \
        Use it when the answer has numbers, comparisons, shares, trends, steps, a process, a timeline or schedule, or \
        structured data; not for a short fact or small talk. Keep the text answer short beside it. \
        Width is about 600 px in the chat and 460 px in the notch (dark there); the page grows to its content \
        (at most 640 px, 260 px in the notch) unless you give height. \
        The page has GlassChat's style: system font, light and dark colors as CSS variables (--fg, --muted, --line, \
        --card, --accent, --green, --red, --orange, --yellow, --purple, --teal) and classes .card, .row, .grid, .stat, \
        .muted, .good, .bad, .bar > i, table. The network is blocked: no external URLs, images or fonts; put data inline. \
        Name the libraries the page uses in libraries; they load before the body. For Chart.js put the canvas in \
        <div style="height:220px"> with options.maintainAspectRatio false. \
        Libraries: \(list.isEmpty ? "none" : list.joined(separator: "; ")). \
        Other npm libraries can be installed with _app_install_library (find it with search_tools). \
        The result reports the page's errors; fix them with a new call.
        """
    }
}
