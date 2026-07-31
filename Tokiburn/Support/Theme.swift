import AppKit
import SwiftUI

enum AppearanceMode: String {
    case light
    case dark

    static let storageKey = "appearanceMode"

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }

    var toggled: AppearanceMode {
        self == .dark ? .light : .dark
    }
}

enum TokiburnTheme {
    static let canvas = adaptive(light: 0xF4F1EC, dark: 0x101113)
    static let surface = adaptive(light: 0xFCFAF6, dark: 0x18191C)
    static let ink = adaptive(light: 0x181715, dark: 0xF5F1EB)
    static let secondary = adaptive(light: 0x716E68, dark: 0xACA8A1)
    static let tertiary = adaptive(light: 0xA29E96, dark: 0x757278)
    static let line = adaptive(light: 0xDCD6CD, dark: 0x353438)
    static let lineSoft = adaptive(light: 0xEAE5DD, dark: 0x252428)
    static let accent = adaptive(light: 0xD9563C, dark: 0xFF775D)
    static let positive = adaptive(light: 0x28785E, dark: 0x61BB95)
    static let warning = adaptive(light: 0xA4622A, dark: 0xDF9555)

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
                return NSColor(hex: bestMatch == .darkAqua ? dark : light)
            }
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
