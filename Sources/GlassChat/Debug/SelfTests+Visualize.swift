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

        // Libraries: the bundled ones by default, removed and added back; downloads from jsDelivr.
        let manifest = VisualLibraries.Manifest()
        expect(manifest.entries.map(\.name) == ["chart.js", "mermaid", "katex"], "bundled libraries by default")
        let removed = manifest.removing("mermaid")
        expect(!removed.entries.contains { $0.name == "mermaid" }, "a bundled library can be removed")
        let mermaid = VisualLibraries.Manifest.bundled.first { $0.name == "mermaid" }!
        expect(removed.adding(mermaid).entries.contains { $0.name == "mermaid" }, "and installed again")
        let d3 = VisualLibraries.Entry(name: "d3", version: "7.9.0", files: ["d3.min.js"], global: "d3", purpose: "custom charts", bundled: false)
        let withD3 = manifest.adding(d3)
        expect(withD3.entries.last == d3 && withD3.removing("d3") == manifest, "an installed library is added and removed")
        let coded = try? JSONDecoder().decode(VisualLibraries.Manifest.self, from: JSONEncoder().encode(withD3))
        expect(coded == withD3, "the manifest is saved as it is")
        expect(VisualLibraries.downloadURL(package: "d3", version: "7.9.0", file: "/dist/d3.min.js").absoluteString
               == "https://cdn.jsdelivr.net/npm/d3@7.9.0/dist/d3.min.js", "a jsDelivr file")
        expect(VisualLibraries.folderName("@observablehq/plot") == "observablehq-plot", "a package's folder name")

        // The model knows the libraries and when to draw.
        let directions = VisualDirectives.description(libraries: withD3.entries)
        expect(directions.contains("chart.js (global Chart)") && directions.contains("d3 (global d3)"), "the libraries are listed")
        expect(directions.contains("libraries"), "how to choose them")
        expect(AppModule.of("glasschat__app_visualize") == .visualize && AppModule.of("glasschat___app_install_library") == .visualize
               && AppModule.of("glasschat___app_remove_library") == .visualize, "visualize tools sit in their module")
        expect(AssistantPrompt.standard.contains("glasschat__app_visualize"), "the assistant is told to visualize")
        expect(AssistantPrompt.previous.count == 2, "the former standard prompt is replaced")

        // A visualize call in the chat becomes what is drawn; other calls do not.
        let call = ToolCall(id: "c1", name: "glasschat__app_visualize",
                            arguments: #"{"html": "<p>Hi</p>", "libraries": ["chart.js"], "height": 200}"#)
        let shown = Visualization(call)
        expect(shown?.html == "<p>Hi</p>" && shown?.libraries == ["chart.js"] && shown?.height == 200, "a visualize call is drawn")
        expect(Visualization(ToolCall(id: "c2", name: "glasschat__app_say", arguments: #"{"text": "Hi"}"#)) == nil, "other calls are not")
        expect(Visualization(ToolCall(id: "c3", name: "glasschat__app_visualize", arguments: "{")) == nil, "half-written arguments are not")
    }
}
#endif
