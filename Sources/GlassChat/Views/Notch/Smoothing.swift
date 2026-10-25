import Foundation

/// Moves a value toward its target with a time constant, so a change of state glides instead of jumping.
enum Smoothing {
    /// After `time` seconds about 63 % of the way; never past the target.
    static func step(current: Double, target: Double, dt: Double, time: Double) -> Double {
        guard time > 0 else { return target }
        return current + (target - current) * (1 - exp(-max(dt, 0) / time))
    }
}

/// Values smoothed from frame to frame of a `TimelineView` (a class: updating it does not redraw by itself).
final class SmoothedValues {
    private var values: [Double] = []
    private var last: Double?

    /// The values one frame closer to `targets`.
    func advance(to targets: [Double], at time: Double, timeConstant: Double) -> [Double] {
        let dt = last.map { min(time - $0, 0.1) } ?? 0
        last = time
        if values.count != targets.count { values = targets; return values }
        values = zip(values, targets).map { Smoothing.step(current: $0, target: $1, dt: dt, time: timeConstant) }
        return values
    }
}
