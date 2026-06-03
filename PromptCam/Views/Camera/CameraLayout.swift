// PromptCam — Unified Camera Screen Layout Constants
// Merged from CameraLayout + CameraChromeLayout (refactor June 1, 2026)
import SwiftUI

/// All camera screen geometry constants in one place.
///
/// - **Preview Geometry**: Aspect ratio and EV drag sensitivity for the
///   focus/exposure reticle (originally `CameraLayout`).
/// - **Header / Footer / Teleprompter Chrome**: Spacing, sizes, and offsets
///   for the overlaid control panels (originally `CameraChromeLayout`).
enum CameraLayout {

    // MARK: - Preview Geometry

    /// Standard 9:16 aspect ratio used to compute preview height from width.
    static let previewAspect: CGFloat = 9.0 / 16.0

    /// Points of vertical drag to traverse the full ±exposure range (10 EV total).
    /// Used by `FocusIndicatorView` EV drag calculations.
    static let evFullRangePoints: CGFloat = 120

    /// Computes top/bottom bar height and preview height from a container size.
    /// - Parameter containerSize: Full safe-area-inset container dimensions.
    /// - Returns: Bar height (half the remaining vertical space) and preview height.
    static func barHeights(containerSize: CGSize) -> (barHeight: CGFloat, previewHeight: CGFloat) {
        let previewHeight = containerSize.width / previewAspect
        let barHeight = max((containerSize.height - previewHeight) / 2, 0)
        return (barHeight, previewHeight)
    }

    // MARK: - Header Chrome
    /// Horizontal inset for header controls (EV pill, grid, format panel).
    static let headerHorizontalPadding: CGFloat = 16

    // MARK: - Recording Cluster
    /// Bottom spacing between record cluster and footer bar.
    static let recordingBottomPadding: CGFloat = 18

    // MARK: - Footer Chrome

    /// Moves footer controls lower to align with approved design.
    static let footerVerticalOffset: CGFloat = 22

    /// Shared circular icon button diameter for footer controls.
    static let footerIconSize: CGFloat = 44

    // MARK: - Teleprompter
    /// Sets teleprompter viewport height (length knob).
    static let teleprompterViewportHeight: CGFloat = 500

    /// Sets distance from preview bottom edge to viewport bottom (position knob).
    static let teleprompterBottomInset: CGFloat = 140

    /// Horizontal inset from the preview right edge for the center-reset button.
    static let teleprompterResetEdgeInset: CGFloat = 26

    /// Diameter of the center-reset button placed where the manual lane used to be.
    static let teleprompterResetButtonSize: CGFloat = 36
}
