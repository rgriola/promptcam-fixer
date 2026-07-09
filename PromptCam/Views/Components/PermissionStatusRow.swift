// PromptCam — Reusable Permission & Settings Row Components
// Extracted from CameraView.swift (refactor June 1, 2026)
// June 25, 2026 — All rows now tap directly to iOS Settings (not just denied)
import SwiftUI

// MARK: - Permission Status Row

/// Tappable row displaying a permission's icon, title, status dot, and label.
/// Tapping any row opens the app's iOS Settings page so the user can
/// review or change any permission at any time — not just denied ones.
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
    /// Permission identifier used for analytics instrumentation.
    let permission: PermissionAnalyticsPermission
    /// Live permission snapshot at tap time. Required for accurate
    /// settings-return diff and recovery-success analytics.
    var snapshot: PermissionPolicySnapshot? = nil

    var body: some View {
        Button {
            PermissionAnalyticsService.trackOpenSettingsTapped(
                permission: permission,
                sourceSurface: .settings,
                snapshot: snapshot
            )
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(Theme.icon16)
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                Text(title)
                    .font(Theme.font16Medium)
                    .foregroundStyle(Theme.white)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(status)
                        .font(Theme.font12Medium)
                        .foregroundStyle(statusColor)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens iOS Settings to manage this permission")
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
