import Foundation
import Observation

/// The script libraries a visualization may use: bundled ones (offline) and ones the model installed from jsDelivr.
/// The list is kept in libraries.json next to their folders in Application Support.
@Observable
@MainActor
final class VisualLibraries {
    static let shared = VisualLibraries()

    struct Entry: Codable, Equatable, Sendable {
        let name: String
        let version: String
        /// Paths in its folder: `.js` files load as scripts, `.css` as styles, in this order.
        let files: [String]
        /// The global it defines (`Chart`), for the model.
        let global: String?
        /// What it is for, for the model.
        let purpose: String
        /// Part of the app; else downloaded into the libraries folder.
        let bundled: Bool
    }

    /// The bundled libraries less the removed ones, then the installed ones (an installed one replaces a bundled
    /// one of its name).
    struct Manifest: Codable, Equatable, Sendable {
        static let bundled: [Entry] = [
            Entry(name: "chart.js", version: "4.6.1", files: ["chart.umd.min.js"], global: "Chart",
                  purpose: "charts: line, bar, pie, doughnut, radar, scatter, bubble (new Chart(canvas, config))", bundled: true),
            Entry(name: "mermaid", version: "11.17.2", files: ["mermaid.min.js"], global: "mermaid",
                  purpose: "diagrams from text: flowcharts, sequence, timelines, gantt, mind maps (<pre class=\"mermaid\">…</pre>, drawn on load)",
                  bundled: true),
            Entry(name: "katex", version: "0.16.11", files: ["katex.min.js", "katex.min.css"], global: "katex",
                  purpose: "math formulas (katex.render(tex, element))", bundled: true),
        ]

        var installed: [Entry] = []
        /// Bundled libraries the model removed.
        var removed: [String] = []

        var entries: [Entry] {
            let replaced = Set(installed.map(\.name))
            return Self.bundled.filter { !removed.contains($0.name) && !replaced.contains($0.name) } + installed
        }

        func adding(_ entry: Entry) -> Manifest {
            var copy = self
            copy.removed.removeAll { $0 == entry.name }
            copy.installed.removeAll { $0.name == entry.name }
            if !entry.bundled { copy.installed.append(entry) }
            return copy
        }

        func removing(_ name: String) -> Manifest {
            var copy = self
            copy.installed.removeAll { $0.name == name }
            if Self.bundled.contains(where: { $0.name == name }), !copy.removed.contains(name) { copy.removed.append(name) }
            return copy
        }
    }

    private(set) var manifest = Manifest()
    var entries: [Entry] { manifest.entries }

    private static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "GlassChat/libraries", directoryHint: .isDirectory)
    }
    private static var manifestURL: URL { folder.appending(path: "libraries.json") }

    private init() {
        if let data = try? Data(contentsOf: Self.manifestURL), let saved = try? JSONDecoder().decode(Manifest.self, from: data) {
            manifest = saved
        }
    }

    func entry(_ name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    /// The folder a library's files are served from.
    func directory(for name: String) -> URL? {
        guard let entry = entry(name) else { return nil }
        if !entry.bundled { return Self.folder.appending(path: name, directoryHint: .isDirectory) }
        if name == "katex" { return Bundle.module.url(forResource: "KaTeX", withExtension: nil) }
        return Bundle.module.url(forResource: "Visualize", withExtension: nil)?.appending(path: "libs/\(name)", directoryHint: .isDirectory)
    }

    private func save(_ new: Manifest) throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(new).write(to: Self.manifestURL, options: .atomic)
        manifest = new
    }

    // MARK: Installing

    static let maxBytes = 10_000_000

    nonisolated static func downloadURL(package: String, version: String, file: String) -> URL {
        let path = file.hasPrefix("/") ? String(file.dropFirst()) : file
        return URL(string: "https://cdn.jsdelivr.net/npm/\(package)@\(version)/\(path)")!
    }

    /// A package's folder and library name: "@observablehq/plot" → "observablehq-plot".
    nonisolated static func folderName(_ package: String) -> String {
        let name = package.lowercased().drop { $0 == "@" }.map { $0 == "/" ? "-" : $0 }
        return String(name).filter { $0.isLetter || $0.isNumber || "-._".contains($0) }
    }

    /// Downloads a package's files (its js and css entry points unless `file` is given) and adds it.
    func install(package: String, version: String?, file: String?, global: String?, purpose: String) async throws -> Entry {
        let resolved = try await Self.resolve(package, version ?? "latest")
        var paths: [String]
        if let file, !file.isEmpty {
            paths = [file]
        } else {
            paths = try await Self.entryPoints(package, resolved)
        }
        guard !paths.isEmpty else { throw MCPError(message: "\(package)@\(resolved) has no entry point; give \"file\".") }
        let name = Self.folderName(package)
        let target = Self.folder.appending(path: name, directoryHint: .isDirectory)
        let staging = FileManager.default.temporaryDirectory.appending(path: "glasschat-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var files: [String] = []
        var total = 0
        for path in paths {
            let (data, response) = try await URLSession.shared.data(from: Self.downloadURL(package: package, version: resolved, file: path))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw MCPError(message: "jsDelivr has no \(path) in \(package)@\(resolved).")
            }
            total += data.count
            guard total <= Self.maxBytes else { throw MCPError(message: "\(package) is larger than 10 MB.") }
            let fileName = (path as NSString).lastPathComponent
            try data.write(to: staging.appending(path: fileName))
            files.append(fileName)
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: staging, to: target)
        // Styles first, so a library's scripts find them.
        let ordered = files.filter { $0.hasSuffix(".css") } + files.filter { !$0.hasSuffix(".css") }
        let entry = Entry(name: name, version: resolved, files: ordered, global: global, purpose: purpose, bundled: false)
        try save(manifest.adding(entry))
        return entry
    }

    /// Adds a bundled library back, if `package` names one.
    func restoreBundled(_ package: String) throws -> Entry? {
        guard let entry = Manifest.bundled.first(where: { $0.name == Self.folderName(package) }) else { return nil }
        try save(manifest.adding(entry))
        return entry
    }

    func remove(_ name: String) throws {
        guard let entry = entry(name) else {
            throw MCPError(message: "There is no library \"\(name)\". Libraries: \(entries.map(\.name).joined(separator: ", ")).")
        }
        if !entry.bundled { try? FileManager.default.removeItem(at: Self.folder.appending(path: name)) }
        try save(manifest.removing(name))
    }

    private static func resolve(_ package: String, _ specifier: String) async throws -> String {
        struct Resolved: Decodable { let version: String? }
        var components = URLComponents(string: "https://data.jsdelivr.com/v1/packages/npm/\(package)/resolved")!
        components.queryItems = [URLQueryItem(name: "specifier", value: specifier)]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        guard let version = try? JSONDecoder().decode(Resolved.self, from: data).version else {
            throw MCPError(message: "jsDelivr does not know \(package)@\(specifier).")
        }
        return version
    }

    private static func entryPoints(_ package: String, _ version: String) async throws -> [String] {
        struct Points: Decodable {
            struct Point: Decodable { let file: String }
            let entrypoints: [String: Point]?
        }
        let url = URL(string: "https://data.jsdelivr.com/v1/packages/npm/\(package)@\(version)/entrypoints")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let points = (try? JSONDecoder().decode(Points.self, from: data))?.entrypoints ?? [:]
        return ["css", "js"].compactMap { points[$0]?.file }
    }
}
