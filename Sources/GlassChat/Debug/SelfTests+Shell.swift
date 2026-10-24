#if DEBUG
import Foundation

extension SelfTests {
    static func shell() {
        // The shell runs off the main thread; the checks wait for it here.
        let chat = UUID()
        let box = ShellChecks()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let runner = ShellRunner()
            box.hi = await runner.run("echo hi", in: chat, timeout: 10)
            box.exit3 = await runner.run("exit 3", in: chat, timeout: 10)
            _ = await runner.run("cd /tmp", in: chat, timeout: 10)
            box.pwd = await runner.run("pwd", in: chat, timeout: 10)
            let start = Date()
            box.slow = await runner.run("sleep 5", in: chat, timeout: 0.5)
            box.slowTook = Date().timeIntervalSince(start)
            box.flood = await runner.run("yes | head -c 100000", in: chat, timeout: 10)
            done.signal()
        }
        done.wait()
        expect(box.hi?.output == "hi" && box.hi?.exitCode == 0, "output and exit code")
        expect(box.exit3?.exitCode == 3, "failing command's code")
        expect(box.pwd?.output.hasSuffix("/tmp") == true, "cd is remembered in the chat")
        expect(box.slow?.timedOut == true && box.slowTook < 4, "timeout stops the command")
        expect((box.flood?.output.count ?? 0) <= ShellRunner.maxOutput + 80 && box.flood?.output.contains("truncated") == true,
               "long output is cut")
    }
}

private final class ShellChecks: @unchecked Sendable {
    var hi, exit3, pwd, slow, flood: ShellRunner.Result?
    var slowTook: TimeInterval = 99
}
#endif
