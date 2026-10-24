import Foundation

/// `app_bash`: commands in zsh (a login shell, for the user's PATH), each chat with its own working folder
/// that a `cd` changes for the next command.
actor ShellRunner {
    static let shared = ShellRunner()
    static let maxOutput = 30_000
    static let defaultTimeout: TimeInterval = 120
    static let maxTimeout: TimeInterval = 600

    struct Result: Sendable {
        let output: String
        let exitCode: Int32
        let timedOut: Bool
    }

    private static let marker = "__GLASSCHAT_PWD__"
    private var folders: [Chat.ID: URL] = [:]

    /// The chat's working folder (the home folder at first).
    func workingDirectory(for chat: Chat.ID) -> URL {
        folders[chat] ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func run(_ command: String, in chat: Chat.ID, timeout: TimeInterval) async -> Result {
        // After the command, the shell prints where it ended up; that becomes the chat's folder.
        let script = "\(command)\n__glasschat_status=$?\nprintf '\\n\(Self.marker)%s' \"$PWD\"\nexit $__glasschat_status"
        let raw = await Self.execute(script, in: workingDirectory(for: chat), timeout: timeout)
        var output = raw.output
        if let range = output.range(of: "\n" + Self.marker, options: .backwards) {
            let folder = String(output[range.upperBound...]).trimmingCharacters(in: .newlines)
            if !folder.isEmpty { folders[chat] = URL(filePath: folder, directoryHint: .isDirectory) }
            output = String(output[..<range.lowerBound])
        }
        output = output.trimmingCharacters(in: .newlines)
        if raw.truncated || output.count > Self.maxOutput {
            output = String(output.prefix(Self.maxOutput)) + "\n… (output truncated to \(Self.maxOutput) characters)"
        }
        return Result(output: output, exitCode: raw.status, timedOut: raw.timedOut)
    }

    /// Runs the script; stops it (and the programs it started) after `timeout` or when the caller is cancelled.
    private static func execute(_ script: String, in folder: URL, timeout: TimeInterval)
        async -> (output: String, status: Int32, timedOut: Bool, truncated: Bool) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-l", "-c", script]
        process.currentDirectoryURL = folder
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let collected = Collected()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collected.append(data) }
        }
        let once = ResumeOnce<Int32>()
        process.terminationHandler = { once.resume($0.terminationStatus) }
        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return ("Could not start zsh: \(error.localizedDescription)", -1, false, false)
        }
        let pid = process.processIdentifier
        let timer = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            collected.timedOut = true
            stop(pid, once)
        }
        let status = await withTaskCancellationHandler {
            await withCheckedContinuation { once.set($0) }
        } onCancel: {
            stop(pid, once)
        }
        timer.cancel()
        // What is still in the pipe.
        try? await Task.sleep(for: .milliseconds(50))
        pipe.fileHandleForReading.readabilityHandler = nil
        return (collected.text, status, collected.timedOut, collected.truncated)
    }

    /// SIGTERM to the shell and its children, SIGKILL two seconds later.
    private static func stop(_ pid: pid_t, _ once: ResumeOnce<Int32>) {
        let children = Process()
        children.executableURL = URL(filePath: "/usr/bin/pkill")
        children.arguments = ["-TERM", "-P", "\(pid)"]
        try? children.run()
        kill(pid, SIGTERM)
        Task {
            try? await Task.sleep(for: .seconds(2))
            kill(pid, SIGKILL)
            once.resume(-1)
        }
    }

    /// The output as it comes, kept to a bounded size.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private(set) var truncated = false
        var timedOut = false

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            // Room for the folder marker after a long output.
            let room = ShellRunner.maxOutput * 4 - data.count
            if room <= 0 { truncated = true; keepTail(chunk); return }
            data.append(chunk.prefix(room))
            if chunk.count > room { truncated = true; keepTail(chunk) }
        }

        /// The last bytes always hold the marker with the folder.
        private var tail = Data()
        private func keepTail(_ chunk: Data) {
            tail.append(chunk)
            if tail.count > 4096 { tail = tail.suffix(4096) }
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            var result = String(decoding: data, as: UTF8.self)
            if truncated, let range = String(decoding: tail, as: UTF8.self).range(of: "\n" + ShellRunner.marker) {
                result += String(String(decoding: tail, as: UTF8.self)[range.lowerBound...])
            }
            return result
        }
    }
}
