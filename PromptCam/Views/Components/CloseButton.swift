// PromptCam — Reusable Close Button Component
import SwiftUI

// CloseButton { dismiss() }
// CloseToolbarButton { dismiss() }

/// Standard close button with xmark icon used across sheets and modal views.
/// Provides consistent styling and behavior for dismissing views.
struct CloseButton: View {
    /// Action to perform when the button is tapped (typically dismiss).
    let action: () -> Void
    
    /// Icon color. Defaults to secondary text for subtle appearance.
    var iconColor: Color = Theme.white
    
    /// Icon size. Defaults to 16pt icon size from Theme.
    var iconSize: Font = Theme.icon20
    
    /// Padding around the tappable area.
    var padding: CGFloat = Theme.space16
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(iconSize)
                .foregroundStyle(iconColor)
                .padding(padding)
                .contentShape(Circle())
        }
        .accessibilityLabel("Close")
        .accessibilityHint("Dismisses the current view")
    }
}

/// Variant for toolbar placement with xmark icon.
/// Used in navigation bars with consistent icon styling.
struct CloseToolbarButton: View {
    /// Action to perform when the button is tapped (typically dismiss).
    let action: () -> Void
    
    /// Button label text for accessibility. Defaults to "Close".
    var label: String = "Close"
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Theme.icon16)
                .foregroundStyle(Theme.white)
        }
        .accessibilityLabel(label)
        .accessibilityHint("Dismisses the current view")
    }
}
