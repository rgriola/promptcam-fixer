// PromptCam — Camera Controls Row
// Extracted from CameraView.swift (refactor June 1, 2026)
// June 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add onTapLock callback for lock toggle button
// June 29, 2026 - Renamed CameraTopControlsView → CameraControlsRowView (controls live at bottom, above footer)
import SwiftUI

// MARK: - Camera Controls Row

/// Camera controls row: video mode badge (left), format pill (center),
/// EV button (center-right), and lock badge (right).
/// Renders as the upper of the two bottom chrome rows, directly above CameraFooterControlsView.
struct CameraControlsRowView: View {
    /// Formatted EV display value shown in the left pill.
    let evText: String
    /// Current focus/exposure lock state shown in the center badge.
    let lockStatus: CameraLockStatus
    /// Current video mode (standard or cinematic).
    let videoMode: VideoMode
    /// Formatted simulated aperture label shown when cinematic mode is active, e.g. "f/2.0".
    /// Nil when cinematic is not active or the device/OS does not support aperture control.
    let apertureText: String?
    /// Resolution label for the format pill (e.g. "HD", "4K").
    let resolutionLabel: String
    /// FPS label for the format pill (e.g. "30", "60").
    let fpsLabel: String

    /// Action for tapping the EV pill.
    let onTapEV: () -> Void
    /// Action for tapping the aperture button (only active when apertureText != nil).
    let onTapAperture: () -> Void
    /// Action for tapping the format quick panel.
    let onTapFormat: () -> Void
    /// Action for tapping the lock status badge to toggle lock state.
    let onTapLock: () -> Void
    /// Whether recording is active — camera control buttons are disabled while recording.
    var isRecording: Bool = false

    /// Header layout containing EV, lock status, grid, and format controls.
    var body: some View {
        HStack {
            Spacer()
            // Video Mode Badge — sizes to content, vertically centered.
            VideoModeBadgeView(
                mode: videoMode,
                apertureText: apertureText,
                onTapAperture: onTapAperture
            )
            .fixedSize()

            Spacer()

            // Format pill: resolution + fps
            Button(action: onTapFormat) {
                HStack(spacing: 0) {
                    Text(resolutionLabel)
                        .font(Theme.mono16Medium)
                        .padding(.trailing, 4)
                    Text(fpsLabel)
                        .font(Theme.mono16Medium)
                        .padding(.trailing, 2)
                    Text("fps")
                        .font(Theme.font12Medium)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.trailing, 4)
                }
                .foregroundStyle(Theme.primaryText)
            }
            .accessibilityLabel("Format panel")
            .accessibilityHint("Opens camera record format settings")

            Spacer()

            // EV button
            Button(action: onTapEV) {
                Text("EV \(evText)")
                    .font(Theme.mono16Medium)
                    .foregroundStyle(Theme.white)
                    .accessibilityLabel("Exposure value")
                    .accessibilityHint("Shows current exposure")
            }

            Spacer()

            // Lock toggle
            CameraLockStatusBadgeView(
                status: lockStatus,
                onToggle: onTapLock,
                isDisabled: videoMode == .cinematic
            )
            Spacer()
        }
        //.padding(.horizontal, Theme.space12)
        //.padding(.bottom, Theme.space8)
        .padding(EdgeInsets(top: 10, leading: Theme.space12, bottom: 4, trailing: Theme.space12))
        .frame(maxWidth: .infinity)
        .background(Theme.black.opacity(0.5))
        .disabled(isRecording)
        .opacity(isRecording ? 0.3 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
    }

}
