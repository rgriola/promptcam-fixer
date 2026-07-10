// PromptCam — Unified Camera Screen Layout
// July 10, 2026 - GitHub Copilot (GPT-5.3-Codex) - Grouped design tokens by
// feature; runtime-size-dependent values (VU meter frame) live in the
// resolver. Consumers read semantic anchors instead of recomputing geometry.
import SwiftUI

// MARK: - CameraLayout (design tokens)

/// Camera screen design tokens grouped by feature.
///
/// Rules:
/// 1. Only pure constants live here. Anything that needs the container size
///    (safe area, preview height, etc.) is resolved in `CameraScreenLayout`.
/// 2. Consumers read grouped tokens (`CameraLayout.Teleprompter.viewportHeight`)
///    rather than a flat namespace so tuning one feature can't affect another.
enum CameraLayout {

    // MARK: Preview

    enum Preview {
        /// 9:16 aspect ratio used to compute preview height from width.
        static let aspect: CGFloat = 9.0 / 16.0

        /// Vertical drag points to traverse the full ±exposure range (10 EV).
        /// Used by `FocusIndicatorView`.
        static let evDragRangePoints: CGFloat = 120
    }

    // MARK: Chrome (header + footer + control envelope)

    enum Chrome {
        /// Horizontal inset for the top controls row (video mode, EV, lock, format).
        static let headerHorizontalPadding: CGFloat = 16

        /// Downward shift applied to the footer controls to match design.
        static let footerVerticalOffset: CGFloat = 22

        /// Shared circular icon button diameter for footer controls.
        static let footerIconSize: CGFloat = 44

        /// Extra vertical room allotted to the controls/footer VStack beyond
        /// the preview height so chrome can extend slightly below the preview.
        static let controlHeightExtra: CGFloat = 100
    }

    // MARK: Record Cluster

    enum RecordCluster {
        /// Diameter of the record button hit target.
        static let buttonDiameter: CGFloat = 72

        /// Distance from the preview's bottom edge to the record button center.
        /// Smaller value pushes the cluster lower.
        static let buttonCenterBottomOffset: CGFloat = 182

        /// Distance from the preview's bottom edge to the recording timer center.
        static let timerCenterBottomOffset: CGFloat = 260
    }

    // MARK: Teleprompter

    enum Teleprompter {
        /// Viewport length (clamped to the preview height at runtime).
        static let viewportHeight: CGFloat = 500

        /// Requested viewport center distance from the preview top.
        /// Clamped at runtime so the viewport stays inside the preview.
        static let centerFromPreviewTop: CGFloat = 0

        /// Upward nudge applied to the resolved viewport center so the
        /// teleprompter clears the top chrome.
        static let centerTopNudge: CGFloat = 75

        /// Horizontal inset from the preview's right edge for the reset /
        /// utility stack.
        static let resetEdgeInset: CGFloat = 35

        /// Single round-variant reset button size (legacy anchor). Utility
        /// stack buttons use `utilityButton*` sizes instead.
        static let resetButtonSize: CGFloat = 40

        /// Shared teleprompter utility button dimensions (Align + Reset).
        static let utilityButtonWidth: CGFloat = 56
        static let utilityButtonHeight: CGFloat = 56
        static let utilityButtonCornerRadius: CGFloat = 8

        /// Vertical spacing between stacked utility buttons.
        static let utilityStackSpacing: CGFloat = 10
    }

    // MARK: VU Meter

    enum VUMeter {
        /// Width of the vertical meter bar.
        static let width: CGFloat = 25

        /// Meter height as a fraction of the preview height.
        static let heightRatio: CGFloat = 0.28

        /// Horizontal inset from the preview's left edge.
        static let horizontalInset: CGFloat = 20

        /// Fine horizontal nudge so the meter clears the preview edge padding.
        static let horizontalNudge: CGFloat = 5
    }

    // MARK: Derived Preview Frame

    /// Top-anchored preview frame. Aspect is preserved; the remaining vertical
    /// space becomes the bottom chrome region.
    /// - Parameter containerSize: Full container dimensions from `GeometryReader`.
    /// - Returns: Preview height (top-pinned) and bottom chrome height.
    static func previewFrame(containerSize: CGSize) -> (
        previewHeight: CGFloat,
        bottomChromeHeight: CGFloat
    ) {
        let rawHeight = containerSize.width / Preview.aspect
        let previewHeight = min(rawHeight, containerSize.height)
        let bottomChromeHeight = max(containerSize.height - previewHeight, 0)
        return (previewHeight, bottomChromeHeight)
    }
}

// MARK: - CameraScreenLayout (resolved anchors)

/// Runtime-resolved screen geometry for a given container size + safe-area.
///
/// Consumers read semantic anchors grouped by feature. `CameraView` should
/// not compute offsets inline — add new derived anchors here instead.
struct CameraScreenLayout {

    // MARK: Feature Sub-anchors

    struct PreviewAnchors {
        let size: CGSize
        let topY: CGFloat
        let bottomY: CGFloat
        let centerX: CGFloat
        let bottomChromeHeight: CGFloat
    }

    struct TeleprompterAnchors {
        let viewportHeight: CGFloat
        /// Final viewport center (top nudge already applied).
        let center: CGPoint
        /// Final viewport bottom Y (top nudge already applied).
        let bottomY: CGFloat
        /// Reset / utility stack anchor (unaffected by the top nudge).
        let resetCenter: CGPoint
        let resetButtonSize: CGFloat
    }

    struct RecordClusterAnchors {
        let recordButtonCenter: CGPoint
        //let recordingTimerCenter: CGPoint
    }

    struct VUMeterAnchors {
        let size: CGSize
        let center: CGPoint
    }

    struct SafeAreaAnchors {
        let topInset: CGFloat
        let bottomInset: CGFloat
    }

    // MARK: Outputs

    let preview: PreviewAnchors
    let teleprompter: TeleprompterAnchors
    let recordCluster: RecordClusterAnchors
    let vuMeter: VUMeterAnchors
    let safeArea: SafeAreaAnchors

    // MARK: Init

    init(containerSize: CGSize, safeAreaInsets: EdgeInsets) {
        // Preview
        let frame = CameraLayout.previewFrame(containerSize: containerSize)
        let topY: CGFloat = 0
        let bottomY = topY + frame.previewHeight
        let centerX = containerSize.width / 2
        let previewSize = CGSize(
            width: containerSize.width,
            height: frame.previewHeight
        )

        self.preview = PreviewAnchors(
            size: previewSize,
            topY: topY,
            bottomY: bottomY,
            centerX: centerX,
            bottomChromeHeight: frame.bottomChromeHeight
        )

        // Teleprompter viewport (clamped to preview bounds)
        let rawViewportH = CameraLayout.Teleprompter.viewportHeight
        let viewportH = min(max(rawViewportH, 0), frame.previewHeight)
        let minCenterY = topY + viewportH / 2
        let maxCenterY = bottomY - viewportH / 2
        let requestedCenterY = topY + CameraLayout.Teleprompter.centerFromPreviewTop
        let rawCenterY = min(max(requestedCenterY, minCenterY), maxCenterY)
        // Apply the top nudge so consumers get a final center.
        let nudgedCenterY = rawCenterY - CameraLayout.Teleprompter.centerTopNudge

        let resetX = containerSize.width - CameraLayout.Teleprompter.resetEdgeInset
        // Reset anchor uses the pre-nudge geometry (matches prior behavior).
        let resetY = rawCenterY + viewportH / 2

        self.teleprompter = TeleprompterAnchors(
            viewportHeight: viewportH,
            center: CGPoint(x: centerX, y: nudgedCenterY),
            bottomY: nudgedCenterY + viewportH / 2,
            resetCenter: CGPoint(x: resetX, y: resetY),
            resetButtonSize: CameraLayout.Teleprompter.resetButtonSize
        )

        // Record cluster
        let recordCenterY = bottomY - CameraLayout.RecordCluster.buttonCenterBottomOffset
       // let timerCenterY = bottomY - CameraLayout.RecordCluster.timerCenterBottomOffset

        self.recordCluster = RecordClusterAnchors(
            recordButtonCenter: CGPoint(x: centerX, y: recordCenterY)
            //,
          //  recordingTimerCenter: CGPoint(x: centerX, y: timerCenterY)
        )

        // VU meter — bottom aligns with the record-button bottom edge.
        let meterHeight = previewSize.height * CameraLayout.VUMeter.heightRatio
        let meterWidth = CameraLayout.VUMeter.width
        let meterCenterX = CameraLayout.VUMeter.horizontalInset
            + CameraLayout.VUMeter.horizontalNudge
        let meterBottomInsetFromPreviewBottom =
            CameraLayout.RecordCluster.buttonCenterBottomOffset
            - CameraLayout.RecordCluster.buttonDiameter / 2
        let meterCenterY = bottomY
            - meterBottomInsetFromPreviewBottom
            - meterHeight / 2

        self.vuMeter = VUMeterAnchors(
            size: CGSize(width: meterWidth, height: meterHeight),
            center: CGPoint(x: meterCenterX, y: meterCenterY)
        )

        // Safe area passthrough
        self.safeArea = SafeAreaAnchors(
            topInset: safeAreaInsets.top,
            bottomInset: safeAreaInsets.bottom
        )
    }
}

/*
Notes for future
There needs to be specific layout markers all Main View elements use:
This app uses the Front Facing - Selfie Camera only. 

Device Screen Width, Devide Screen Height; Uniform defined one time for entire app global values
CameraPreview Width = Device Screen Width reguardless of Camera Format ie; 4k, HD etc. 
CameraPreview Height = 9 x 16 ratio (this is not correct Camera shoots HD, UHD and 4k)
 
Camera Preview View Alignment:
Camera is vertical presenting. Camera Preview Top is aligned with Device Screen Top - vetically aligned. 
CameraPreview Bottom ends based on the 9x16 ratio, 1920 for HD or tranlated for Device Screen Pixels.  

Camera Preview bottom is the start of the Top-Line and Footer buttons.
Teleprompter Top aligns with Screen Device Top, overlays Camera Preview.

Teleprompter Bottom:
VU Meter, Record Cluster, Utility Controls Frame is between Prompter Bottom and Preview Bottom
Camera Controls; [VU][Record Cluster][Utility]


*/
