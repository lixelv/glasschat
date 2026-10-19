import Foundation

/// Added for GlassChat: how far an inline image is moved from the text baseline.
/// An inline image provider records it (negative = below the baseline) before it returns the image.
public final class InlineImageMetrics: @unchecked Sendable {
  public static let shared = InlineImageMetrics()

  private let lock = NSLock()
  private var offsets: [String: CGFloat] = [:]

  public func setBaselineOffset(_ offset: CGFloat, for source: String) {
    self.lock.lock()
    defer { self.lock.unlock() }
    self.offsets[source] = offset
  }

  public func baselineOffset(for source: String) -> CGFloat {
    self.lock.lock()
    defer { self.lock.unlock() }
    return self.offsets[source] ?? 0
  }
}
