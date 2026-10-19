import AppKit
import SwiftUI

/// The app's colours. Dark: the system apps' dark palette (Notes, Mail); light: a matching placeholder.
/// Each follows the system appearance.
enum Palette {
    static let sidebar = dynamic(dark: 0x272626, light: 0xF2F1F0)
    static let content = dynamic(dark: 0x1E1E1E, light: 0xFFFFFF)
    static let separator = dynamic(dark: 0x4F4E4D, light: 0xD9D8D7)
    static let text = dynamic(dark: 0xE4E4E4, light: 0x1D1D1F)
    static let secondaryText = dynamic(dark: 0xAFAEAE, light: 0x6E6E73)

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
