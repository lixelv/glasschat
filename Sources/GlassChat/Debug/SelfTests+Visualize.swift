#if DEBUG
import Foundation

extension SelfTests {
    static func visualize() {
        let chart = VisualLibraries.Entry(name: "chart.js", version: "4.4.1", files: ["chart.umd.min.js"], global: "Chart",
                                          purpose: "charts", bundled: true)
        let katex = VisualLibraries.Entry(name: "katex", version: "0.16.11", files: ["katex.min.js", "katex.min.css"], global: "katex",
                                          purpose: "formulas", bundled: true)
        let page = VisualPage.html(body: "<canvas id=c></canvas>", libraries: [chart, katex])
        expect(page.hasPrefix("<!doctype html>") && page.contains("<meta charset=\"utf-8\">"), "a page of its own")
        expect(page.contains("<link rel=\"stylesheet\" href=\"glasschat-viz://style/glass.css\">"), "the common style")
        expect(page.contains("<script src=\"glasschat-viz://lib/chart.js/chart.umd.min.js\"></script>"), "a chosen library's script")
        expect(page.contains("<link rel=\"stylesheet\" href=\"glasschat-viz://lib/katex/katex.min.css\">"), "a chosen library's style")
        expect(page.contains("<body><canvas id=c></canvas></body>"), "the model's body")
        let report = page.range(of: "post('error'")
        let library = page.range(of: "glasschat-viz://lib/")
        expect(report != nil && page.contains("post('height'"), "height and errors are reported")
        expect(report.map { r in library.map { r.lowerBound < $0.lowerBound } ?? false } == true, "errors of libraries are reported too")
        expect(!VisualPage.html(body: "<p>Hi</p>", libraries: []).contains("glasschat-viz://lib/"), "no library, no script")

        // The scheme serves only what is inside a library's folder.
        let folder = URL(filePath: "/tmp/libs/chart.js")
        expect(VisualSandbox.file(in: folder, path: "chart.umd.min.js")?.path == "/tmp/libs/chart.js/chart.umd.min.js", "a library file")
        expect(VisualSandbox.file(in: folder, path: "../../etc/passwd") == nil, "no way out of the folder")
        expect(VisualSandbox.mimeType("x.js") == "text/javascript" && VisualSandbox.mimeType("x.css") == "text/css"
               && VisualSandbox.mimeType("f.woff2") == "font/woff2", "types of served files")
    }
}
#endif
