import AppKit
import SwiftUI

/// Mineral palette. Rodinia was a supercontinent, so the colours come from rock:
/// granite for the resting plates, lapis while they move, olivine once joined.
enum Palette {
    static let ink = Color(light: 0x1E2A30, dark: 0xE6ECEE)          // basalt
    static let inkSoft = Color(light: 0x5B6B73, dark: 0x8FA0A8)
    static let stoneLight = Color(light: 0xC9D0D2, dark: 0x6F7B82)    // granite
    static let stoneDeep = Color(light: 0x8C989E, dark: 0x414C53)
    static let lapis = Color(light: 0x3D5A80, dark: 0x86A8D4)
    static let olivineLight = Color(light: 0x63A07F, dark: 0x74C49A)
    static let olivineDeep = Color(light: 0x2F6B52, dark: 0x3C8763)
    static let garnet = Color(light: 0xA8423C, dark: 0xE07A70)
    static let hairline = Color(light: 0x1E2A30, dark: 0xE6ECEE).opacity(0.09)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Typeface {
    /// New York carries the one line that matters: the connection state.
    static func headline(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11.5)
    static let figures = Font.system(size: 12, weight: .medium).monospacedDigit()
}
