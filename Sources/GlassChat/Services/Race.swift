import Foundation

/// Resumes a continuation once, whichever side comes first (a result, a timeout, a cancellation).
final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var early: T?
    private var done = false

    func set(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        if done, let early { lock.unlock(); continuation.resume(returning: early); return }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(_ value: T) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: value)
        } else {
            early = value
            lock.unlock()
        }
    }
}

/// The task's value, or nil after `timeout` seconds or as soon as the caller is cancelled,
/// even when the task itself does not stop (it is cancelled, and left to end on its own).
func value<T: Sendable>(of task: Task<T, Never>, timeout: Double? = nil) async -> T? {
    let once = ResumeOnce<T?>()
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            once.set(continuation)
            Task { once.resume(await task.value) }
            if let timeout {
                Task {
                    try? await Task.sleep(for: .seconds(timeout))
                    once.resume(nil)
                }
            }
        }
    } onCancel: {
        task.cancel()
        once.resume(nil)
    }
}
