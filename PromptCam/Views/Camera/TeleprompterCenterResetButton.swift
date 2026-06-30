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
            VStack(spacing: 3) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(Theme.icon16)
                    .foregroundStyle(Theme.white)
                Text("Center")
                    .font(Theme.font10Regular)
                    .foregroundStyle(Theme.primaryText)
            }
            .roundedBackground()
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous)) // ← tap target matches shape
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.3 : 1)
        .accessibilityLabel("Reset script position")
        .accessibilityHint("Centers script to the teleprompter center.")
    }
}
