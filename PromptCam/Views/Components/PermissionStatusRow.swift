// PromptCam — Reusable Permission & Settings Row Components
// Extracted from CameraView.swift (refactor June 1, 2026)
import SwiftUI

// MARK: - Permission Status Row

/// Row displaying a permission's icon, title, status dot, label, and optional
/// "Settings" link for denied permissions. Used in both the settings sheet and
/// any future permission-related UI.
struct PermissionStatusRow: View {
    /// SF Symbol name for the permission icon.
    let icon: String
    /// Tint color for the permission icon.
    let iconColor: Color
    /// Permission title (e.g. "Camera", "Microphone").
    let title: String
    /// Human-readable status label (e.g. "Granted", "Denied").
    let status: String
    /// Semantic color matching the authorization state.
    let statusColor: Color
    /// Whether the permission is denied/restricted — shows "Settings" link.
    let isDenied: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Theme.icon16)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            Text(title)
                .font(Theme.font16Medium)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(status)
                    .font(Theme.font12Medium)
                    .foregroundStyle(statusColor)
            }

            if isDenied {
                OpenSettingsButton()
            }
        }
    }
}

// MARK: - Setting Status Row

/// Simple key/value row used in settings list sections (e.g. "Version: 1.0 (1)").
struct SettingStatusRow: View {
    /// Left-side label for the setting item.
    let title: String
    /// Right-side value text for the setting item.
    let value: String

    /// Two-column status row used in settings sections.
    var body: some View {
        HStack {
            Text(title)
                .font(Theme.font16Medium)
                .foregroundStyle(Theme.white)

            Spacer()

            Text(value)
                .font(Theme.font16Medium)
                .foregroundStyle(Theme.white)
        }
    }
}
