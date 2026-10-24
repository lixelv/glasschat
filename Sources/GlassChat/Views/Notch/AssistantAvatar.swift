import SwiftUI

/// The assistant's face: a soft white squircle with two eyes that breathes, blinks, listens, thinks and talks.
struct AssistantAvatar: View {
    enum Mood: Equatable { case idle, listening, thinking, speaking, error }

    let mood: Mood
    /// The voice level (listening) or the output level (speaking), 0…1.
    let level: Double
    var size: CGFloat = 28

    @State private var nextBlink = Date.now.addingTimeInterval(3)

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let blinking = context.date >= nextBlink && context.date < nextBlink.addingTimeInterval(0.12)
            Canvas { gc, canvas in
                draw(gc, in: canvas, t: t, blinking: blinking)
            }
            .onChange(of: context.date >= nextBlink.addingTimeInterval(0.12)) { _, passed in
                if passed { nextBlink = .now.addingTimeInterval(.random(in: 3...6)) }
            }
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .accessibilityLabel("Assistant")
    }

    private func draw(_ gc: GraphicsContext, in canvas: CGSize, t: Double, blinking: Bool) {
        var gc = gc
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        var scaleX = 1.0, scaleY = 1.0, lift = 0.0, tilt = 0.0
        switch mood {
        case .idle:
            let breath = 1 + 0.03 * sin(t * 2 * .pi / 3.5)
            scaleX = breath; scaleY = breath
        case .listening:
            scaleY = 1 + level * 0.12
            scaleX = 1 - level * 0.05
            lift = -level * 3
        case .error:
            tilt = 4 * sin(t * 2 * .pi / 2) * .pi / 180
        default: break
        }
        gc.translateBy(x: center.x, y: center.y + lift)
        gc.rotate(by: .radians(tilt))
        gc.scaleBy(x: scaleX, y: scaleY)

        let s = size
        let body = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
        gc.fill(Path(roundedRect: body, cornerRadius: s * 0.32, style: .continuous), with: .color(.white))

        var eyeOffset = CGPoint.zero
        if mood == .thinking { eyeOffset = CGPoint(x: s * 0.06, y: -s * 0.08) }
        for side in [-1.0, 1.0] {
            let eye = CGPoint(x: side * s * 0.18 + eyeOffset.x, y: -s * 0.04 + eyeOffset.y)
            if mood == .error {
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

        if mood == .speaking {
            let w = s * 0.26, h = s * (0.04 + level * 0.14)
            gc.fill(Path(roundedRect: CGRect(x: -w / 2, y: s * 0.2 - h / 2, width: w, height: h), cornerRadius: h / 2),
                    with: .color(.black))
        }

        if mood == .thinking {
            for i in 0..<3 {
                let angle = t * 2 * .pi / 1.2 + Double(i) * 2 * .pi / 3
                let p = CGPoint(x: cos(angle) * s * 0.62 / scaleX, y: sin(angle) * s * 0.62 / scaleY)
                let d = s * 0.08
                gc.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)), with: .color(.white.opacity(0.6)))
            }
        }
    }
}
