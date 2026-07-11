// May 29, 2026 - 11:23pm - GitHub Copilot
// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add teleprompterHPad constant
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

enum VUColor {
    static let peak = Color(hex: "#00FA47") // top color
    static let stepFour = Color(hex: "#00CC3A")       
    static let stepThree = Color(hex: "#FAC400")
    static let stepTwo = Color(hex: "#CCA000")
    static let stepOne = Color(hex: "#F5F5F5")
    static let floor = Color(hex: "#FFFFFF")
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
    static let icon14 = fontFamily.font(size: 14)
    static let icon16 = fontFamily.font(size: 16)
    static let icon20 = fontFamily.font(size: 20)
    static let icon24 = fontFamily.font(size: 24)
    static let icon28 = fontFamily.font(size: 28)
    static let icon32 = fontFamily.font(size: 32)
    static let icon34 = fontFamily.font(size: 34)
    static let icon38 = fontFamily.font(size: 38)
    static let icon44 = fontFamily.font(size: 44)


    // Display
    static let display24 = fontFamily.font(size: 24)
    static let display32 = fontFamily.font(size: 32)
    static let display44 = fontFamily.font(size: 44, weight: .bold)
    static let display64 = fontFamily.font(size: 64)

    // Colors
    static let black = Color(hex: "#111111")
    static let white = Color(hex: "#F5F5F5")
    static let accent = Color(hex: "#FFD700")
    // FFD700/ Goldish for Oscar 

    static let blue = Color(hex: "#0012CC")
    static let green = Color(hex: "#00CC3A")
    static let red = Color(hex: "#cc0000")
    static let redTwo = Color(hex: "#a80000")
   
    static let yellow = Color(hex: "#FFD60A")
    static let yellowTwo = Color(hex: "#CCA000")



    static let gray = Color(hex: "#8E8E93")

    static let cameraBg = Color(hex: "#0B0B0B")
    static let panelBg = Color(hex: "#111111")
    static let separator = Color(hex: "#F5F5F5").opacity(0.5)
    static let overlayScrim = Color(hex: "#000000")

    static let primaryText = Color(hex: "#F5F5F5")
    static let secondaryText = Color(hex: "#A1A1A6")
    static let tertiaryText = Color(hex: "#6E6E73")
    static let blackText = Color(hex: "#111111")

    static let glassOverlay = Color.white.opacity(0.2)
    static let glassBorder = Color.white.opacity(0.12)

    // Materials
    static let glassMaterial: Material = .ultraThinMaterial

    // Radii
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 20

    // Teleprompter
    static let teleprompterHPad: CGFloat = 24

    // Animations
    /// Standard spring for panel show/hide transitions (EV, aperture, adjustment).
    static let panelSpring: Animation = .spring(response: 0.35, dampingFraction: 0.8)

    // Spacing
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32

    static let headerSpace36: CGFloat = 36

    static let purple = Color(hex: "#8576EE")

    /*static let bgGrad = LinearGradient(
                            colors: [Theme.black, Theme.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                            )
    */

    static let bgGrad = LinearGradient(
                            colors: [Theme.black, Theme.redTwo],
                            startPoint: .leading,
                            endPoint: .bottomTrailing
                            )
}

// MARK: - View Extensions
extension View {
    /// Applies a subtle card background: dark fill with light border.
    func cardBackground(
        cornerRadius: CGFloat = Theme.radiusMd) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Theme.black.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Theme.white.opacity(0.3), lineWidth: 1)
                }
        }
    }

    func roundedBackground(
        fill: Color = Theme.black.opacity(0.3)
        ) -> some View {
            self.background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
                    .padding(-10)
            }
    }

    func settingsSectionHeaderStyle() -> some View {
        self
            .listRowBackground(Theme.black.opacity(0.1))
            .foregroundStyle(Theme.white)
    }

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

// Drag Gesture based control
/*
 Component API
struct CameraStyleSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tickCount: Int = 9
    let formatLabel: (Double) -> String  // e.g., "+0.3" or "50%"
    let onReset: () -> Void
    let onDismiss: () -> Void
}
3. Implementation Layers
Layer 1: Container (Capsule Background)
Dark capsule (60-70pt height, full available width minus padding)
.background(.ultraThinMaterial.opacity(0.8)) or solid dark gray
Overlay blur/shadow for depth

Layer 2: Track with Tick Marks
HStack approach:
ForEach(0..<tickCount) → thin gray Rectangles (1-2pt wide, 12-16pt tall)
Equal spacing via Spacer() between each
Alternative Canvas approach: Draw lines at calculated X positions for pixel-perfect spacing

Layer 3: Yellow Indicator Line
Vertical Rectangle (2-3pt wide, 24-32pt tall, Theme.yellow)
Position via .offset(x: thumbOffset)
Calculate: thumbOffset = (value - range.lowerBound) / (range.upperBound - range.lowerBound) * trackWidth - (trackWidth / 2)
Needs GeometryReader to get trackWidth

Layer 4: Value Label
Text above indicator line, same X offset
Format via formatLabel(value) closure
Consider adding +/- prefix logic

Layer 5: Action Buttons
Left X button: Calls onDismiss()
Right reset button: Calls onReset()
SF Symbols: xmark and arrow.counterclockwise
Fixed width (~40-48pt each)

@GestureState private var isDragging = false

DragGesture(minimumDistance: 0)
    .updating($isDragging) { _, state, _ in state = true }
    .onChanged { gesture in
        // Convert gesture.location.x to normalized 0...1
        let normalized = gesture.location.x / trackWidth
        let newValue = range.lowerBound + normalized * (range.upperBound - range.lowerBound)
        value = newValue.clamped(to: range)
        
        // Optional: UIImpactFeedbackGenerator at tick boundaries
    }

5. Integration Points
Replace existing sliders in:

TeleprompterAdjustmentPanel.swift (3 sliders)
Any future camera exposure/focus/zoom controls
Theme additions needed:

Theme.sliderTickGray (for tick marks)
Theme.sliderIndicatorYellow (or reuse existing yellow)
Possibly Theme.sliderCapsuleBg
6. Optional Enhancements
Phase 1 (MVP):

Basic drag gesture + visual feedback
Reset/dismiss buttons
Value label
Phase 2 (Polish):

Haptic feedback at notch boundaries
Smooth spring animation when reset
Accessibility: VoiceOver adjustable trait
Double-tap on track to jump to value
Phase 3 (Advanced):

Snapping to tick positions (discrete mode)
Min/max labels at track ends
Vertical orientation option
7. Testing Strategy
Manual:

Drag across full range, verify min/max boundaries
Test reset button snaps to default
Verify dismiss closes without changing value
Check on different screen sizes (SE, Pro Max)
Unit tests:

Value clamping logic
Offset calculation (value → pixel position)
Reverse calculation (pixel position → value)

*/
