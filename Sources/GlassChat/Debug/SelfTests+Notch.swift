#if DEBUG
import Foundation

extension SelfTests {
    static func notch() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 32, auxiliaryLeftWidth: 662, auxiliaryRightWidth: 662, menuBarHeight: 32)
               == CGRect(x: 662, y: 950, width: 188, height: 32), "hardware notch")
        expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
               == CGRect(x: 666, y: 958, width: 180, height: 24), "pill uses menu bar height")
        expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 0).height == 32, "pill default 32")
        let n = CGSize(width: 188, height: 32)
        expect(NotchGeometry.shapeSize(.closed, notch: n, contentHeight: 300) == n, "closed")
        expect(NotchGeometry.shapeSize(.hover, notch: n, contentHeight: 0) == CGSize(width: 260, height: 36), "hover +36/side +4")
        expect(NotchGeometry.shapeSize(.busy, notch: n, contentHeight: 0) == CGSize(width: 244, height: 32), "busy +28/side")
        expect(NotchGeometry.shapeSize(.expanded, notch: n, contentHeight: 200) == CGSize(width: 480, height: 232), "expanded fits")
        expect(NotchGeometry.shapeSize(.expanded, notch: n, contentHeight: 900, maxHeight: 520).height == 520, "expanded max")
        // The open notch grows down with the answer, to two thirds of the screen.
        expect(NotchGeometry.maxExpandedHeight(screenHeight: 982) == 655, "two thirds of the screen")
        expect(NotchGeometry.shapeSize(.expanded, notch: n, contentHeight: 600, maxHeight: 655).height == 632, "it grows with the answer")
        expect(NotchGeometry.shapeSize(.expanded, notch: n, contentHeight: 2000, maxHeight: 655).height == 655, "up to two thirds")

        // What a click does, by where it happened (its own location, not where the pointer is later).
        let shape = CGRect(x: 510, y: 450, width: 492, height: 532)
        expect(NotchGeometry.click(at: CGPoint(x: 756, y: 960), shape: shape, expanded: false) == .expand, "click on the folded notch")
        expect(NotchGeometry.click(at: CGPoint(x: 756, y: 960), shape: shape, expanded: true) == NotchGeometry.Click.none, "click inside the open notch")
        expect(NotchGeometry.click(at: CGPoint(x: 808, y: 574), shape: CGRect(x: 510, y: 900, width: 492, height: 82), expanded: true) == .collapse, "click elsewhere folds it")
        expect(NotchGeometry.click(at: CGPoint(x: 100, y: 100), shape: shape, expanded: false) == NotchGeometry.Click.none, "click elsewhere while folded")
        // While the assistant listens, thinks or speaks, only Esc, the shortcut and Stop fold it.
        expect(NotchGeometry.click(at: CGPoint(x: 808, y: 574), shape: CGRect(x: 510, y: 900, width: 492, height: 82), expanded: true, busy: true) == NotchGeometry.Click.none, "click elsewhere while busy keeps it open")
    }
}
#endif
