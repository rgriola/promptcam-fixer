// May 29, 2026 - 11:23pm - GitHub Copilot
import SwiftUI

enum FontFamily {
    case system
    case custom(String)

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight)
        case .custom(let name):
            return .custom(name, size: size)
        }
    }

    func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    func rounded(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum Theme {
    static let fontFamily: FontFamily = .system

    // Typography (even sizes only)
    static let font10Regular = fontFamily.font(size: 10)
    static let font10Medium = fontFamily.font(size: 10, weight: .medium)
    static let font10Semibold = fontFamily.font(size: 10, weight: .semibold)

    static let font12Regular = fontFamily.font(size: 12)
    static let font12Medium = fontFamily.font(size: 12, weight: .medium)
    static let font12Semibold = fontFamily.font(size: 12, weight: .semibold)

    static let font16Regular = fontFamily.font(size: 16)
    static let font16Medium = fontFamily.font(size: 16, weight: .medium)
    static let font16Semibold = fontFamily.font(size: 16, weight: .semibold)
    static let font16Bold = fontFamily.font(size: 16, weight: .bold)

    static let font20Semibold = fontFamily.font(size: 20, weight: .semibold)
    static let font20Bold = fontFamily.font(size: 20, weight: .bold)

    static let font28Light = fontFamily.font(size: 28, weight: .light)
    static let font28Bold = fontFamily.font(size: 28, weight: .bold)

    // Monospaced
    static let mono10Medium = fontFamily.mono(size: 10, weight: .medium)
    static let mono12Medium = fontFamily.mono(size: 12, weight: .medium)
    static let mono16Medium = fontFamily.mono(size: 16, weight: .medium)
    static let mono16Bold = fontFamily.mono(size: 16, weight: .bold)

    // Icons
    static let icon12 = fontFamily.font(size: 12)
    static let icon16 = fontFamily.font(size: 16)
    static let icon20 = fontFamily.font(size: 20)

    // Display
    static let display24 = fontFamily.font(size: 24)
    static let display32 = fontFamily.font(size: 32)
    static let display44 = fontFamily.font(size: 44, weight: .bold)
    static let display64 = fontFamily.font(size: 64)

    // Colors
    static let black = Color(hex: "#111111")
    static let white = Color(hex: "#F5F5F5")

    static let blue = Color(hex: "#1E7AF0")
    static let blueScrollPreview = Color(hex: "#3C74BD")

    static let green = Color(hex: "#30D158")
    static let red = Color(hex: "#FF3B30")
    static let redRecordPreview = Color(hex: "#CC5650")

    static let yellow = Color(hex: "#FFD60A")
    static let gray = Color(hex: "#8E8E93")

    static let cameraBg = Color(hex: "#0B0B0B")
    static let panelBg = Color(hex: "#1C1C1E")
    static let separator = Color(hex: "#2C2C2E")
    static let overlayScrim = Color(hex: "#000000")

    static let primaryText = Color(hex: "#F5F5F5")
    static let secondaryText = Color(hex: "#A1A1A6")
    static let tertiaryText = Color(hex: "#6E6E73")

    static let glassOverlay = Color.white.opacity(0.08)
    static let glassBorder = Color.white.opacity(0.12)

    // Materials
    static let glassMaterial: Material = .ultraThinMaterial

    // Radii
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 20

    // Spacing
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32

    static let headerSpace36: CGFloat = 36
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
