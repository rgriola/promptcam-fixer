// PromptCam — Top Header Controls
// Extracted from CameraView.swift (refactor June 1, 2026)
// June 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add onTapLock callback for lock toggle button
import SwiftUI

// MARK: - Top Header Controls

/// Top-row camera controls: EV pill (left), lock status badge (center),
/// grid toggle (right), and format quick-panel (second row, left).
struct CameraTopControlsView: View {
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

    /// Header layout containing EV, lock status, grid, and format controls.
    var body: some View {
        // Header rows are intentionally compact to preserve preview space.
            HStack {
                
                // Change this to format Toggles HD > 4K | 24 - 30 + Cine
                Button(action: onTapFormat) {
                    HStack(spacing: 0){
                        Text(resolutionLabel)
                            .font(Theme.font16Semibold)
                            .padding(.trailing, 4)
                        /*
                        Text("res")
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.trailing, 4)
                        */

                        Text(fpsLabel)
                            .font(Theme.font16Semibold)
                            .padding(.trailing, 2)
                        Text("fps")
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.trailing, 4)
                    }
                    .foregroundStyle(Theme.primaryText) // Font colors and style.
                }
                .accessibilityLabel("Format panel")
                .accessibilityHint("Opens camera record format settings")

                Spacer()

                // Video Mode Badge (shows STD or CINE)
                VideoModeBadgeView(mode: videoMode)

                // Cinematic aperture button — only visible when cinematic mode + iOS 26+ aperture available.
                if let apertureText {
                    // removed spacer to being elements closer
                    Button(action: onTapAperture) {
                        Text(apertureText)
                            .font(Theme.mono16Medium)
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Simulated aperture")
                            .accessibilityHint("Adjusts depth-of-field blur in cinematic mode")
                    }
                }


                Spacer()
                // Move to Bottom to Control EV with Dial
                Button(action: onTapEV) {
                    Text("EV \(evText)")
                        .font(Theme.mono16Medium)
                        .foregroundStyle(Theme.white)
                        .accessibilityLabel("Exposure value")
                        .accessibilityHint("Shows current exposure")
                }

                

                Spacer()

                // Change to Toggle Lock and Auto
                CameraLockStatusBadgeView(
                    status: lockStatus,
                    onToggle: onTapLock,
                    isDisabled: videoMode == .cinematic
                )
            }
            .padding(.horizontal, Theme.space12)
            .padding(.bottom, Theme.space8)
            .frame(maxWidth: .infinity)
    }

}
