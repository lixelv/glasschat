import AppKit

enum NotchState: Equatable {
    case closed, busy, hover, expanded
}

/// Where the notch is and how big the shape over it gets.
enum NotchGeometry {
    static let expandedWidth: CGFloat = 480
    /// Before the screen is known.
    static let defaultMaxHeight: CGFloat = 520
    /// Wider on each side while hovered or working.
    static let hoverGrow: CGFloat = 36
    static let busyGrow: CGFloat = 28

    /// The notch in screen coordinates, or a pill at the top centre of a screen without one.
    static func notchRect(screenFrame: CGRect, safeAreaTop: CGFloat, auxiliaryLeftWidth: CGFloat?,
                          auxiliaryRightWidth: CGFloat?, menuBarHeight: CGFloat) -> CGRect {
        if safeAreaTop > 0, let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
            return CGRect(x: screenFrame.minX + left, y: screenFrame.maxY - safeAreaTop,
                          width: screenFrame.width - left - right, height: safeAreaTop)
        }
        let height = menuBarHeight > 0 ? menuBarHeight : 32
        let width: CGFloat = 180
        return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// The open notch grows down with what it shows, to two thirds of the screen.
    static func maxExpandedHeight(screenHeight: CGFloat) -> CGFloat {
        (screenHeight * 2 / 3).rounded()
    }

    static func shapeSize(_ state: NotchState, notch: CGSize, contentHeight: CGFloat, maxHeight: CGFloat = defaultMaxHeight) -> CGSize {
        switch state {
        case .closed: notch
        case .hover: CGSize(width: notch.width + 2 * hoverGrow, height: notch.height + 4)
        case .busy: CGSize(width: notch.width + 2 * busyGrow, height: notch.height)
        case .expanded: CGSize(width: expandedWidth, height: min(notch.height + contentHeight, maxHeight))
        }
    }

    enum Click: Equatable { case expand, collapse, none }

    /// What a click at a screen point does: open the folded notch, fold the open one when it is elsewhere —
    /// unless the assistant is busy (listening, thinking, speaking): then only Esc, the shortcut and Stop fold it.
    static func click(at point: CGPoint, shape: CGRect, expanded: Bool, busy: Bool = false) -> Click {
        let inside = shape.contains(point)
        if inside { return expanded ? .none : .expand }
        return expanded && !busy ? .collapse : .none
    }

    /// The built-in screen with a notch, else the main one.
    @MainActor
    static func screen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    @MainActor
    static func notchRect(on screen: NSScreen) -> CGRect {
        notchRect(screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                  auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width, auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
                  menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }
}
