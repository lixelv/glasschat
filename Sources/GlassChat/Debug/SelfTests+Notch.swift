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
        expect(NotchGeometry.shapeSize(.expanded, notch: n, contentHeight: 900).height == 520, "expanded max")
    }
}
#endif
