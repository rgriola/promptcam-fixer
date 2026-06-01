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
    /// Device safe-area top inset used for notch-aware placement.
    let safeTopInset: CGFloat
    /// Action for tapping the EV pill.
    let onTapEV: () -> Void
    /// Action for tapping the grid toggle button.
    let onTapGrid: () -> Void
    /// Action for tapping the format quick panel.
    let onTapFormat: () -> Void

    /// Header layout containing EV, lock status, grid, and format controls.
    var body: some View {
        // Header rows are intentionally compact to preserve preview space.
        VStack(spacing: 0) {
            HStack {
                Button(action: onTapEV) {
                    Text("EV \(evText)")
                        .font(Theme.mono10Medium)
                        .foregroundStyle(Theme.white)
                        .padding(.horizontal, Theme.space12)
                        .padding(.vertical, Theme.space8)
                        .background(Theme.panelBg.opacity(0.9), in: Capsule())
                        .accessibilityLabel("Exposure value")
                        .accessibilityHint("Shows current exposure")
                }

                Spacer()

                CameraLockStatusBadgeView(status: lockStatus)

                Spacer()

                Button(action: onTapGrid) {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(Theme.icon20)
                        .foregroundStyle(Theme.white)
                        .padding(10)
                        .background(Theme.panelBg.opacity(0.9), in: Circle())
                        .accessibilityLabel("Toggle grid")
                        .accessibilityHint("Shows or hides the composition grid")
                }
            }
            .padding(.top, max(safeTopInset - 200, 0))

            HStack {
                Button(action: onTapFormat) {
                    HStack(spacing: Theme.space8) {
                        Text(resolutionLabel)
                            .font(Theme.font16Semibold)
                        Text("RES")
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.secondaryText)
                        Divider()
                            .frame(height: 14)
                            .overlay(Theme.separator)
                        Text(fpsLabel)
                            .font(Theme.font16Semibold)
                        Text("FPS")
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, Theme.space12)
                    .padding(.vertical, Theme.space8)
                    .background(Theme.panelBg.opacity(0.9), in: Capsule())
                }
                .accessibilityLabel("Format panel")
                .accessibilityHint("Opens camera record format settings")

                Spacer()
            }
        }
        .padding(.horizontal, CameraLayout.headerHorizontalPadding)
        .frame(maxWidth: .infinity)
    }
}
