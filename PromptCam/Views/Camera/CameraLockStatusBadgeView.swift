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
            let parts = status.displayParts
            ZStack(alignment: .center) {
                // Invisible anchor — always holds the largest possible height
                // (AUTO at mono16 + "Lock" at mono12) so the header HStack
                // never sees a size change when the badge switches states.
                VStack(spacing: 0) {
                    Text("AUTO")
                        .font(Theme.mono16Medium)
                    Text("Lock")
                        .font(Theme.mono12Medium)
                }
                .opacity(0)
                .accessibilityHidden(true)

                // Real content — overlaid and centered inside the stable frame.
                VStack(spacing: 0) {
                    Text(parts.top)
                        .font(parts.bottom == nil ? Theme.mono16Medium : Theme.mono12Medium)
                    // Always render the bottom slot; invisible when AUTO.
                    Text(parts.bottom ?? " ")
                        .font(Theme.mono12Medium)
                        .opacity(parts.bottom == nil ? 0 : 1)
                }
            }
            .foregroundStyle(statusColor)
            .opacity(isDisabled ? 0.4 : 1.0)
        }
        .disabled(status == .unsupported || isDisabled)
        .accessibilityLabel("Focus/Exposure lock")
        .accessibilityHint(isDisabled ? "Auto Only in Cine Mode" : (status.isLocked ? "Tap to unlock" : "Tap to lock"))
        .accessibilityValue(status.text)
    }
}
