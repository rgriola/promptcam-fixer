// PromptCam — Lock Status Badge
// Extracted from CameraView.swift (refactor June 1, 2026)
import SwiftUI

// MARK: - Lock Status Badge

/// Capsule pill that surfaces the current autofocus/exposure lock state.
/// Shows "AUTO" (green), a lock variant (yellow), or "LOCK UNAVAILABLE" (yellow).
struct CameraLockStatusBadgeView: View {
    /// Lock status used to derive badge text and color.
    let status: CameraLockStatus

    /// Semantic color for current lock state.
    private var statusColor: Color {
        switch status {
        case .auto:
            return Theme.green
        case .unsupported:
            return Theme.yellow
        case .aeAfLocked, .aeLocked, .afLocked:
            return Theme.yellow
        }
    }

    /// Badge pill that surfaces current autofocus/exposure state.
    var body: some View {
        Text(status.text)
            .font(Theme.mono16Medium)
            .foregroundStyle(statusColor)
            .accessibilityLabel("Focus and exposure lock status")
            .accessibilityValue(status.text)
    }
}
