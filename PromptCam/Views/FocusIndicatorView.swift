// May 29, 2026 - 11:23pm - GitHub Copilot
// June 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Simplify to thin yellow rectangle (iOS Camera style)
import SwiftUI

/// Simplified focus indicator: thin yellow rectangle (matches iOS Camera app).
/// Shows briefly after focus tap or lock toggle, then fades after 3 seconds.
/// Future enhancement: Could use face detection to dynamically size/position the frame.
struct FocusIndicatorView: View {
    let showFocusIndicator: Bool
    
    var body: some View {
        if showFocusIndicator {
            Rectangle()
                .strokeBorder(Theme.yellow, lineWidth: 2)
                .frame(width: 80, height: 80)
                .transition(.opacity)
                .accessibilityLabel("Focus indicator")
                .accessibilityHint("Shows current focus point")
        }
    }
}
