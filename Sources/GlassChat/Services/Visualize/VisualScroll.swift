import CoreGraphics

/// The wheel over a visualization: the page scrolls while it can, the chat at its edges and when it fits.
enum VisualScroll {
    /// Whether the chat takes the gesture; nil while it has not moved yet.
    static func decision(deltaX: CGFloat, deltaY: CGFloat, scrollY: CGFloat, contentHeight: CGFloat, frameHeight: CGFloat) -> Bool? {
        guard deltaX != 0 || deltaY != 0 else { return nil }
        return passesOn(deltaX: deltaX, deltaY: deltaY, scrollY: scrollY, contentHeight: contentHeight, frameHeight: frameHeight)
    }

    /// `deltaY` > 0 scrolls toward the top (as `NSEvent.scrollingDeltaY`).
    static func passesOn(deltaX: CGFloat, deltaY: CGFloat, scrollY: CGFloat, contentHeight: CGFloat, frameHeight: CGFloat) -> Bool {
        if abs(deltaX) > abs(deltaY) { return false }
        if contentHeight <= frameHeight + 1 { return true }
        if deltaY > 0 { return scrollY <= 0.5 }
        if deltaY < 0 { return scrollY + frameHeight >= contentHeight - 1 }
        return true
    }
}
