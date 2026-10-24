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
        let (status, output) = try await Self.run(cli, ["-m", modelFile.path, "-f", wav.path, "-l", "auto", "-nt", "-np"], errors: false)
        guard status == 0 else { throw MCPError(message: "whisper-cli failed: \(output.suffix(300))") }
        return output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func download() async throws {
        state = .downloading(0)
        let partial = modelFile.appendingPathExtension("part")
        let (bytes, response) = try await URLSession.shared.bytes(from: Self.modelURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MCPError(message: "The Whisper model could not be downloaded.") }
        let total = max(response.expectedContentLength, 1)
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        var buffer = Data()
        var written: Int64 = 0
        buffer.reserveCapacity(1 << 20)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                state = .downloading(Double(written) / Double(total))
            }
        }
        try handle.write(contentsOf: buffer)
        try handle.close()
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
