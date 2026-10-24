import SwiftUI

/// The notch's outline: a straight top with small concave "ears" at its corners, rounded at the bottom.
/// The ears stick out `earRadius` on each side of the body.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var earRadius: CGFloat = 6

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = earRadius
        let b = min(bottomRadius, (rect.width - 2 * r) / 2, rect.height - r)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY + r), control: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r - b, y: rect.maxY), control: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r + b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY - b), control: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX + r, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
