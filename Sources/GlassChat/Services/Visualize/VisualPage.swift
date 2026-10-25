import Foundation

/// The page around what the model wrote for `app_visualize`: the common style, the chosen libraries, and a script
/// that tells the app the page's height and its errors (it comes first, so the libraries' errors count too).
enum VisualPage {
    static let scheme = "glasschat-viz"

    static func html(body: String, libraries: [VisualLibraries.Entry]) -> String {
        var head = [
            "<meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width\">",
            "<link rel=\"stylesheet\" href=\"\(scheme)://style/glass.css\">",
            "<script>\(report)</script>",
        ]
        for library in libraries {
            for file in library.files {
                let url = "\(scheme)://lib/\(library.name)/\(file)"
                if file.hasSuffix(".css") {
                    head.append("<link rel=\"stylesheet\" href=\"\(url)\">")
                } else {
                    head.append("<script src=\"\(url)\"></script>")
                }
            }
        }
        head.append("<script src=\"\(scheme)://style/glass.js\"></script>")
        return "<!doctype html>\n<html><head>\n" + head.joined(separator: "\n") + "\n</head><body>" + body + "</body></html>"
    }

    /// Posts `height` whenever the page's size changes, `error` for every uncaught error, and `ready` once loaded.
    private static let report = """
    (function () {
      const post = (name, value) => { try { webkit.messageHandlers[name].postMessage(value) } catch (e) {} };
      window.addEventListener('error', e => post('error', String(e.message || e) + (e.lineno ? ' (line ' + e.lineno + ')' : '')));
      window.addEventListener('unhandledrejection', e => post('error', 'Unhandled promise rejection: ' + String(e.reason)));
      const size = () => post('height', Math.ceil(document.documentElement.scrollHeight));
      window.addEventListener('load', () => {
        size();
        new ResizeObserver(size).observe(document.body);
        setTimeout(() => post('ready', true), 400);
      });
    })();
    """
}
