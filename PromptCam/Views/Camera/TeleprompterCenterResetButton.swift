// PromptCam — Teleprompter Center Reset Button
// Extracted from CameraView.swift (refactor June 1, 2026)
import SwiftUI

// MARK: - Teleprompter Center Reset Button

/// Single round control placed where the legacy manual lane used to sit.
/// Snaps the first line of script to the teleprompter viewport vertical center.
struct TeleprompterCenterResetButton: View {
    /// Disables interaction (and dims) while recording.
    let isDisabled: Bool
    /// Callback fired on tap to perform the center-reset action.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.panelBg.opacity(0.9))
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(Theme.icon16)
                    .foregroundStyle(Theme.white)
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel("Reset script position")
        .accessibilityHint("Centers the first line of script in the teleprompter viewport.")
    }
}
