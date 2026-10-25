import SwiftUI

/// The assistant's face: a soft white squircle with two eyes. It breathes and blinks, bounces while listening,
/// muses with a soft glow while thinking, moves its mouth while speaking; changes of mood glide (~0.4 s).
struct AssistantAvatar: View {
    enum Mood: Equatable { case idle, listening, thinking, speaking, error }

    let mood: Mood
    /// The voice level (listening) or the output level (speaking), 0…1.
    let level: Double
    var size: CGFloat = 28

    @State private var nextBlink = Date.now.addingTimeInterval(3)
    @State private var smoothed = SmoothedValues()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let blinking = context.date >= nextBlink && context.date < nextBlink.addingTimeInterval(0.12)
            let p = Pose(smoothed.advance(to: Pose.target(mood, level: level, time: t).values, at: t, timeConstant: 0.13))
            Canvas { gc, canvas in
                draw(gc, in: canvas, pose: p, blinking: blinking)
            }
            .onChange(of: context.date >= nextBlink.addingTimeInterval(0.12)) { _, passed in
                if passed { nextBlink = .now.addingTimeInterval(.random(in: 3...6)) }
            }
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .accessibilityLabel("Assistant")
    }

    /// Everything the drawing depends on, as numbers that can glide from one mood to the next.
    private struct Pose {
        var scaleX = 1.0, scaleY = 1.0, lift = 0.0, tilt = 0.0
        var eyeX = 0.0, eyeY = 0.0, mouth = 0.0, glow = 0.0, sad = 0.0

        var values: [Double] { [scaleX, scaleY, lift, tilt, eyeX, eyeY, mouth, glow, sad] }

        init(_ v: [Double]) {
            (scaleX, scaleY, lift, tilt, eyeX, eyeY, mouth, glow, sad) = (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8])
        }

        init() {}

        static func target(_ mood: Mood, level: Double, time t: Double) -> Pose {
            var p = Pose()
            switch mood {
            case .idle:
                let breath = 1 + 0.03 * sin(t * 2 * .pi / 3.5)
                p.scaleX = breath; p.scaleY = breath
            case .listening:
                p.scaleY = 1 + level * 0.12
                p.scaleX = 1 - level * 0.05
                p.lift = -level * 3
            case .thinking:
                // Slow breathing, eyes drifting along a Lissajous curve, a soft glow.
                let breath = sin(t * 2 * .pi / 2.4)
                p.scaleX = 1 + 0.02 * breath; p.scaleY = p.scaleX
                p.eyeX = 0.05 * sin(t * 2 * .pi / 3)
                p.eyeY = -0.03 + 0.025 * sin(t * 4 * .pi / 3 + 1)
                p.glow = 0.11 + 0.05 * breath
            case .speaking:
                p.mouth = 0.04 + level * 0.14
            case .error:
                p.tilt = 4 * sin(t * 2 * .pi / 2) * .pi / 180
                p.sad = 1
            }
            return p
        }
    }

    private func draw(_ gc: GraphicsContext, in canvas: CGSize, pose p: Pose, blinking: Bool) {
        var gc = gc
        let s = size
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        if p.glow > 0.005 {
            let r = s * 0.75
            gc.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                    with: .color(.white.opacity(p.glow)))
        }
        gc.translateBy(x: center.x, y: center.y + p.lift)
        gc.rotate(by: .radians(p.tilt))
        gc.scaleBy(x: p.scaleX, y: p.scaleY)

        let body = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
        gc.fill(Path(roundedRect: body, cornerRadius: s * 0.32, style: .continuous), with: .color(.white))

        for side in [-1.0, 1.0] {
            let eye = CGPoint(x: side * s * 0.18 + p.eyeX * s, y: -s * 0.04 + p.eyeY * s)
            if p.sad > 0.5 {
                var arc = Path()
                arc.addArc(center: CGPoint(x: eye.x, y: eye.y + s * 0.06), radius: s * 0.08,
                           startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                gc.stroke(arc, with: .color(.black), lineWidth: 2)
            } else {
                let height = blinking ? s * 0.02 : s * 0.22
                gc.fill(Path(ellipseIn: CGRect(x: eye.x - s * 0.07, y: eye.y - height / 2, width: s * 0.14, height: height)),
                        with: .color(.black))
            }
        }

        if p.mouth > 0.01 {
            let w = s * 0.26, h = s * p.mouth
            gc.fill(Path(roundedRect: CGRect(x: -w / 2, y: s * 0.2 - h / 2, width: w, height: h), cornerRadius: h / 2),
                    with: .color(.black))
        }
    }
}
