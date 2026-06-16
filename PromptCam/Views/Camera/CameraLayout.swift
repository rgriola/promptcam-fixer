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
    /// 
    static let previewAspect: CGFloat = 9.0 / 16.0 // 0.5625 aspect ratio

    /// Points of vertical drag to traverse the full ±exposure range (10 EV total).
    /// Used by `FocusIndicatorView` EV drag calculations.
    static let evFullRangePoints: CGFloat = 120

    /// Top-anchored preview frame. Aspect is preserved; remaining vertical space
    /// becomes the bottom chrome region reserved for future controls.
    /// - Parameter containerSize: Full container dimensions from `GeometryReader`.
    /// - Returns: Preview height (top-pinned) and bottom chrome height.
    static func previewFrame(containerSize: CGSize) -> (
        previewHeight: CGFloat,
        bottomChromeHeight: CGFloat)
        {
        let rawHeight = containerSize.width / previewAspect
        let previewHeight = min(rawHeight, containerSize.height)
        let bottomChromeHeight = max(containerSize.height - previewHeight, 0)
        return (previewHeight, bottomChromeHeight)
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

    /// SINGLE position knob — distance from preview top to viewport center.
    /// Increase to move the teleprompter down; decrease to move it up.
    /// Value is clamped at runtime so the viewport stays fully inside the preview.
    static let teleprompterCenterFromPreviewTop: CGFloat = 0

    /// This move the horiz pos of both text and button
    static let teleprompterResetEdgeInset: CGFloat = 25

    /// button Size. 
    static let teleprompterResetButtonSize: CGFloat = 36

    // MARK: - VU Meter

    /// Width of the vertical VU meter bar.
    static let vuMeterWidth: CGFloat = 50

    /// Horizontal inset from the left edge of the preview.
    static let vuMeterHorizontalInset: CGFloat = 30

    /// Top and bottom padding inside the preview for the meter.
    static let vuMeterVerticalPadding: CGFloat = 200
}

// MARK: - Resolved Layout

/// Resolved camera-screen geometry for a given container size + safe-area insets.
///
/// Centralizes all derived values (preview frame, teleprompter viewport, reset
/// button anchor) so `CameraView` reads ready-to-use coordinates instead of
/// recomputing math in its `GeometryReader`. Edit constants in `CameraLayout`;
/// add new derived values here.
struct CameraScreenLayout {

    // Preview frame (top-anchored)
    let previewSize: CGSize
    let previewTopY: CGFloat
    let previewBottomY: CGFloat
    let previewCenterX: CGFloat
    let bottomChromeHeight: CGFloat

    // Teleprompter viewport
    let teleprompterViewportHeight: CGFloat
    let teleprompterCenter: CGPoint
    let teleprompterBottomY: CGFloat

    // Reset button
    let teleprompterResetButtonSize: CGFloat
    let teleprompterResetCenter: CGPoint

    // Safe-area passthrough for chrome padding.
    let safeTopInset: CGFloat
    let safeBottomInset: CGFloat

    init(containerSize: CGSize, 
         safeAreaInsets: EdgeInsets) 
        {
        let frame = CameraLayout.previewFrame(containerSize: containerSize)
        
        let topY: CGFloat = 0
        let bottomY = topY + frame.previewHeight
        let centerX = containerSize.width / 2

        self.previewSize = CGSize(
            width: containerSize.width, 
            height: frame.previewHeight
            )

        self.previewTopY = topY
        self.previewBottomY = bottomY
        self.previewCenterX = centerX
        self.bottomChromeHeight = frame.bottomChromeHeight

        // Clamp viewport to stay fully inside the preview frame.
        let rawViewportH = CameraLayout.teleprompterViewportHeight

        let viewportH = min(max(rawViewportH, 0), frame.previewHeight)
        
        let minCenterY = topY + viewportH / 2 // clamp
        let maxCenterY = bottomY - viewportH / 2 // clamp
        
        let requestedCenterY = topY + CameraLayout.teleprompterCenterFromPreviewTop
       
        let centerY = min(max(requestedCenterY, minCenterY), maxCenterY)

        self.teleprompterViewportHeight = viewportH

        self.teleprompterCenter = CGPoint(x: centerX, y: centerY)

        self.teleprompterBottomY = centerY + viewportH / 2

        // Reset button hugs the right edge at the viewport bottom.
        let resetX = containerSize.width - CameraLayout.teleprompterResetEdgeInset
        self.teleprompterResetButtonSize = CameraLayout.teleprompterResetButtonSize
        self.teleprompterResetCenter = CGPoint(x: resetX, y: centerY + viewportH / 2)

        self.safeTopInset = safeAreaInsets.top
        self.safeBottomInset = safeAreaInsets.bottom
    }
}
