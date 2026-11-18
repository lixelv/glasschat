#if DEBUG
import Foundation

/// Checks of the pure logic, run with GLASSCHAT_SELF_TEST=1 (scripts/selftest.sh):
/// no test framework builds with the Command Line Tools alone.
@MainActor
enum SelfTests {
    private static var failures: [String] = []
    private static var count = 0

    /// Each area adds its checks here.
    private static let suites: [@MainActor () -> Void] = [context, silence, speechText, askUser, notch, models, language, shortcut, hover, hidden, fileTools, shell, approval, voice, reviewFixes, hallucination, waveform, pause, smoothing, bargeIn, tokens, modules, visualize, sandbox, pushToTalk, clipboard]

    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["GLASSCHAT_SELF_TEST"] == "1" else { return }
        for suite in suites { suite() }
        if failures.isEmpty {
            print("SELF-TEST: all \(count) passed")
        } else {
            print("SELF-TEST: \(failures.count) of \(count) failed")
            failures.forEach { print($0) }
        }
        exit(failures.isEmpty ? 0 : 1)
    }

    static func expect(_ condition: Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
        count += 1
        if !condition { failures.append("\(file):\(line) \(name)") }
    }
}
#endif
