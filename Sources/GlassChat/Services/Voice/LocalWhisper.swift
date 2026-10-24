import AppKit
import Foundation
import Observation

/// Whisper on this Mac: whisper.cpp from Homebrew (`whisper-cli`) and a model file in Application Support.
@Observable
@MainActor
final class LocalWhisper {
    static let shared = LocalWhisper()

    enum State: Equatable {
        case checking
        /// Homebrew is not installed; the user installs it in Terminal (it asks for their password).
        case needsHomebrew
        case needsInstall
        case installing(String)
        /// The model file, 0…1.
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var state = State.checking
    /// whisper-server keeps the model loaded: a phrase takes a second instead of reloading it each time.
    private var server: Process?
    private static let serverURL = URL(string: "http://127.0.0.1:2077/inference")!

    static let modelName = "ggml-large-v3-turbo-q5_0.bin"
    static let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!
    private nonisolated static let prefixes = ["/opt/homebrew/bin", "/usr/local/bin"]

    private var modelFile: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "GlassChat/whisper", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: Self.modelName)
    }

    private init() {}

    private func tool(_ name: String) -> URL? {
        Self.prefixes.map { URL(filePath: "\($0)/\(name)") }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Looks at what is installed.
    func refresh() {
        switch state {
        case .installing, .downloading: return
        default: break
        }
        if tool("whisper-cli") != nil && FileManager.default.fileExists(atPath: modelFile.path) {
            state = .ready
        } else if tool("brew") == nil {
            state = .needsHomebrew
        } else {
            state = .needsInstall
        }
    }

    /// Installs whisper.cpp with Homebrew and downloads the model; without Homebrew, opens Terminal to install both.
    func install() async {
        refresh()
        if state == .needsHomebrew {
            openTerminalInstaller()
            return
        }
        do {
            if tool("whisper-cli") == nil, let brew = tool("brew") {
                state = .installing("Installing whisper.cpp with Homebrew…")
                let (status, output) = try await Self.run(brew, ["install", "whisper.cpp"], environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
                guard status == 0 else { throw MCPError(message: "brew install whisper.cpp failed: \(output.suffix(300))") }
            }
            if !FileManager.default.fileExists(atPath: modelFile.path) {
                try await download()
            }
            state = .checking
            refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The text of a WAV file, in whatever language it is spoken.
    func transcribe(_ wav: URL) async throws -> String {
        guard let cli = tool("whisper-cli"), FileManager.default.fileExists(atPath: modelFile.path) else {
            throw MCPError(message: "Whisper is not installed yet: Settings → Assistant → Install.")
        }
        if await warmUp() {
            do { return try await transcribeOnServer(wav) }
            catch {
                // Folding the notch cancels the phrase: that is not a failure to make up for.
                if Task.isCancelled { throw CancellationError() }
                voiceLog.error("whisper-server failed, using whisper-cli: \(error.localizedDescription, privacy: .public)")
            }
        }
        let (status, output) = try await Self.run(cli, ["-m", modelFile.path, "-f", wav.path, "-l", "auto", "-nt", "-np"], errors: false)
        guard status == 0 else { throw MCPError(message: "whisper-cli failed: \(output.suffix(300))") }
        return output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Starts whisper-server (once) and waits until it answers; false when it cannot run.
    @discardableResult
    func warmUp() async -> Bool {
        if let warming { return await warming.value }
        let task = Task { await startServer() }
        warming = task
        let ready = await task.value
        warming = nil
        return ready
    }

    private var warming: Task<Bool, Never>?

    private func startServer() async -> Bool {
        if let server, server.isRunning, await Self.serverAnswers() { return true }
        stopServer()
        guard let program = tool("whisper-server"), FileManager.default.fileExists(atPath: modelFile.path) else { return false }
        let process = Process()
        process.executableURL = program
        process.arguments = ["-m", modelFile.path, "-l", "auto", "-nt", "--host", "127.0.0.1", "--port", "2077"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        server = process
        // Loading the model takes a few seconds.
        for _ in 0..<60 {
            if await Self.serverAnswers() { return true }
            guard process.isRunning else { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    func stopServer() {
        server?.terminate()
        server = nil
    }

    private nonisolated static func serverAnswers() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:2077/")!)
        request.timeoutInterval = 1
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    private func transcribeOnServer(_ wav: URL) async throws -> String {
        var form = MultipartForm()
        form.add(file: "file", filename: "speech.wav", mimeType: "audio/wav", data: try Data(contentsOf: wav))
        form.add("response_format", "text")
        var request = URLRequest(url: Self.serverURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw MCPError(message: "whisper-server answered \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// With curl: URLSession turns down the address Hugging Face's CDN redirects to ("bad URL").
    private func download() async throws {
        state = .downloading(0)
        let curl = URL(filePath: "/usr/bin/curl")
        let partial = modelFile.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partial)
        // The size, from the headers of the last redirect.
        let (_, headers) = try await Self.run(curl, ["-sIL", Self.modelURL.absoluteString])
        let total = headers.split(separator: "\n").last { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Double($0.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") } ?? 0
        let watch = Task { @MainActor in
            while !Task.isCancelled {
                let size = (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? Double) ?? 0
                if total > 0 { state = .downloading(min(size / total, 1)) }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        defer { watch.cancel() }
        let (status, output) = try await Self.run(curl, ["-fsSL", "-o", partial.path, Self.modelURL.absoluteString])
        guard status == 0 else {
            // curl 6/7: the name did not resolve, or to 0.0.0.0 — what DNS filters do.
            if status == 6 || status == 7 {
                throw MCPError(message: "Hugging Face's download server (*.hf.co) cannot be reached. A DNS filter or ad blocker (AdGuard…) may block it: allow *.hf.co, then press Install again.")
            }
            throw MCPError(message: "The Whisper model could not be downloaded: \(output.suffix(200))")
        }
        try? FileManager.default.removeItem(at: modelFile)
        try FileManager.default.moveItem(at: partial, to: modelFile)
    }

    /// A `.command` file runs in Terminal: Homebrew's own installer (it asks for the password), then whisper.cpp.
    private func openTerminalInstaller() {
        let script = """
        #!/bin/bash
        echo "Installing Homebrew and whisper.cpp for GlassChat…"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
        brew install whisper.cpp
        echo "Done. Go back to GlassChat and press Install again to download the model."
        """
        let url = FileManager.default.temporaryDirectory.appending(path: "Install Whisper for GlassChat.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Runs a program; its status and its output (stdout, with stderr unless `errors` is false, read as it comes so a long
    /// output never fills the pipe).
    private nonisolated static func run(_ program: URL, _ arguments: [String], environment: [String: String] = [:], errors: Bool = true) async throws -> (Int32, String) {
        try await Task.detached {
            let process = Process()
            process.executableURL = program
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (prefixes + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
            env.merge(environment) { $1 }
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errors ? pipe : FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
