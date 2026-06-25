// PromptCam — Lock Status Badge
// Extracted from CameraView.swift (refactor June 1, 2026)
// June 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Convert to toggle button
import SwiftUI

// MARK: - Lock Status Badge

/// Toggle button that controls autofocus/exposure lock state.
/// Shows "AUTO" (green), a lock variant (yellow), or "LOCK UNAVAILABLE" (yellow).
/// Tap to toggle between locked and auto modes.
/// Disabled in cinematic mode (continuous autofocus only).
struct CameraLockStatusBadgeView: View {
    /// Lock status used to derive badge text and color.
    let status: CameraLockStatus
    /// Callback invoked when user taps the button to toggle lock state.
    let onToggle: () -> Void
    /// Whether the lock toggle is disabled (e.g., in cinematic mode).
    var isDisabled: Bool = false

    /// Semantic color for current lock state.
    private var statusColor: Color {
        switch status {
        case .auto:
            return Theme.white
        case .unsupported:
            return Theme.red
        case .aeAfLocked, .aeLocked, .afLocked:
            return Theme.yellow
        }
    }

    /// Toggle button that controls autofocus/exposure lock.
    var body: some View {
        Button(action: onToggle) {
            Text(status.text)
                .font(Theme.mono16Medium)
                .foregroundStyle(statusColor)
                .opacity(isDisabled ? 0.4 : 1.0)
        }
        .disabled(status == .unsupported || isDisabled)
        .accessibilityLabel("Focus and exposure lock")
        .accessibilityHint(isDisabled ? "Not available in cinematic mode" : (status.isLocked ? "Tap to unlock" : "Tap to lock"))
        .accessibilityValue(status.text)
    }
}
