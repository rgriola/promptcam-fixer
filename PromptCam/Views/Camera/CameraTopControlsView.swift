// PromptCam — Top Header Controls
// Extracted from CameraView.swift (refactor June 1, 2026)
import SwiftUI

// MARK: - Top Header Controls

/// Top-row camera controls: EV pill (left), lock status badge (center),
/// grid toggle (right), and format quick-panel (second row, left).
struct CameraTopControlsView: View {
    /// Formatted EV display value shown in the left pill.
    let evText: String
    /// Current focus/exposure lock state shown in the center badge.
    let lockStatus: CameraLockStatus
    /// Resolution label for the format pill (e.g. "HD", "4K").
    let resolutionLabel: String
    /// FPS label for the format pill (e.g. "30", "60").
    let fpsLabel: String

    /// Action for tapping the EV pill.
    let onTapEV: () -> Void
    /// Action for tapping the grid toggle button.
    let onTapGrid: () -> Void
    /// Action for tapping the format quick panel.
    let onTapFormat: () -> Void

    /// Header layout containing EV, lock status, grid, and format controls.
    var body: some View {
        // Header rows are intentionally compact to preserve preview space.
            HStack {
                
                Button(action: onTapFormat) {
                    HStack{
                        Text(resolutionLabel)
                            .font(Theme.font16Semibold)
                            .padding(.trailing, 1)
                        Text("res")
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.trailing, 4)

                        Text(fpsLabel)
                            .font(Theme.font16Semibold)
                            .padding(.trailing, 1)
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

                Button(action: onTapEV) {
                    Text("EV \(evText)")
                        .font(Theme.mono16Medium)
                        .foregroundStyle(Theme.white)
                        .accessibilityLabel("Exposure value")
                        .accessibilityHint("Shows current exposure")
                }

                Spacer()

                CameraLockStatusBadgeView(status: lockStatus)

                Spacer()

                // Guide Dog Icon / Button
                Button(action: onTapGrid) {

                    Image(systemName: "service.dog.fill")
                        .scaleEffect(x: -1, y: 1)
                        .font(Theme.icon20)
                        .foregroundStyle(Theme.white)
                        .accessibilityLabel("Toggle grid")
                        .accessibilityHint("Shows or hides the composition grid")
                }
            }
          //  .padding(.horizontal, CameraLayout.headerHorizontalPadding)
            .padding(.horizontal, Theme.space12)
            .padding(.top, Theme.space4) // Add space for notch.
            .background(Theme.panelBg.opacity(0.9))
            .frame(maxWidth: .infinity)
    }

}
