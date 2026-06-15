// PromptCam — Reusable Save Button Component
import SwiftUI

// SaveToolbarButton { /* action */ }
// SaveToolbarButton(isDisabled: isEmpty) { /* action */ }

/// Standard save button with checkmark icon used across sheets and modal views.
/// Provides consistent styling and behavior for saving/confirming actions.
struct SaveButton: View {
    /// Action to perform when the button is tapped (typically save and dismiss).
    let action: () -> Void
    
    /// Whether the button is disabled (e.g., invalid input).
    var isDisabled: Bool = false
    
    /// Icon color. Defaults to accent color.
    var iconColor: Color = Theme.accent
    
    /// Icon size. Defaults to 20pt icon size from Theme.
    var iconSize: Font = Theme.icon20
    
    /// Padding around the tappable area.
    var padding: CGFloat = Theme.space16
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(iconSize)
                .foregroundStyle(iconColor)
                .padding(padding)
                .contentShape(Circle())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .accessibilityLabel("Save")
        .accessibilityHint("Saves changes and dismisses the current view")
    }
}

/// Variant for toolbar placement with text label.
/// Used in navigation bars where system styling is preferred.
struct SaveToolbarButton: View {
    /// Action to perform when the button is tapped (typically save and dismiss).
    let action: () -> Void
    
    /// Whether the button is disabled (e.g., invalid input).
    var isDisabled: Bool = false
    
    /// Button label text. Defaults to "Save".
    var label: String = "Save"
    
    /// Padding around the tappable area.
    var padding: CGFloat = Theme.space16
    
    var body: some View {
          Button(action: action) {
               Image(systemName: "checkmark")
                    .font(Theme.icon16)
                    .foregroundStyle(Theme.white)
          }
          .disabled(isDisabled)
          .accessibilityLabel(label)
          .accessibilityHint("Saves changes and dismisses the current view")
       
    }
}
