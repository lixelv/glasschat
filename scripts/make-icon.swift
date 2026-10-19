// Renders Resources/AppIcon.icns: a blue squircle with a glassy highlight and a white chat symbol.
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let path = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(calibratedRed: 0.36, green: 0.62, blue: 1, alpha: 1),
                        NSColor(calibratedRed: 0.20, green: 0.33, blue: 0.95, alpha: 1)])!.draw(in: path, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let shine = NSBezierPath(ovalIn: NSRect(x: inset.minX - 150, y: inset.midY, width: inset.width + 300, height: inset.height))
    NSColor.white.withAlphaComponent(0.16).setFill()
    shine.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.35).setStroke()
    path.lineWidth = 6
    path.stroke()
    let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
    }
    return true
}

let set = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    let names = px == 1024 ? ["icon_512x512@2x"] : px == 16 ? ["icon_16x16"]
        : ["icon_\(px)x\(px)", "icon_\(px / 2)x\(px / 2)@2x"]
    for name in names { try! data.write(to: set.appending(path: "\(name).png")) }
}
