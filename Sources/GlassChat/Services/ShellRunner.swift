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
    /// The chat's working folder; the home folder at first, or when the folder is gone (removed, ejected).
    func workingDirectory(for chat: Chat.ID) -> URL {
        var isDirectory: ObjCBool = false
        guard let folder = folders[chat], FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            folders[chat] = nil
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return folder
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

    /// Runs the script in a process group of its own; stops the whole group (the programs the command started
    /// too) after `timeout` or when the caller is cancelled.
    private static func execute(_ script: String, in folder: URL, timeout: TimeInterval)
        async -> (output: String, status: Int32, timedOut: Bool, truncated: Bool) {
        var pipe: [Int32] = [0, 0]
        guard Darwin.pipe(&pipe) == 0 else { return ("Could not open a pipe.", -1, false, false) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, pipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, pipe[1], 2)
        posix_spawn_file_actions_addclose(&actions, pipe[0])
        posix_spawn_file_actions_addclose(&actions, pipe[1])
        posix_spawn_file_actions_addchdir_np(&actions, folder.path)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        let arguments = ["/bin/zsh", "-l", "-c", script]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, "/bin/zsh", &actions, &attributes, &argv, environ)
        close(pipe[1])
        guard spawned == 0 else {
            close(pipe[0])
            return ("Could not start zsh: \(String(cString: strerror(spawned)))", -1, false, false)
        }

        let group = pid
        let collected = Collected()
        let reader = FileHandle(fileDescriptor: pipe[0], closeOnDealloc: true)
        // Read until the end of the output: when the whole group is gone, the pipe closes.
        let reading = Task.detached {
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                collected.append(data)
            }
        }
        let once = ResumeOnce<Int32>()
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(group, &status, 0) == -1 && errno == EINTR {}
            // WIFEXITED / WEXITSTATUS; a signal gives -1.
            once.resume((status & 0x7f) == 0 ? (status >> 8) & 0xff : -1)
        }
        let timer = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            collected.markTimedOut()
            stop(group: group)
        }
        let status = await withTaskCancellationHandler {
            await withCheckedContinuation { once.set($0) }
        } onCancel: {
            stop(group: group)
        }
        timer.cancel()
        // Whatever is left: the rest of the group, then what is in the pipe.
        stop(group: group, gently: false)
        await reading.value
        return (collected.text, status, collected.timedOut, collected.truncated)
    }

    /// SIGTERM to the whole group, SIGKILL two seconds later (at once when `gently` is false).
    private static func stop(group: pid_t, gently: Bool = true) {
        guard gently else { kill(-group, SIGKILL); return }
        kill(-group, SIGTERM)
        Task.detached {
            try? await Task.sleep(for: .seconds(2))
            kill(-group, SIGKILL)
        }
    }

    /// The output as it comes, kept to a bounded size.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private(set) var truncated = false
        private(set) var timedOut = false

        func markTimedOut() {
            lock.lock()
            timedOut = true
            lock.unlock()
        }

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
