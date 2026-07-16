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

    // MARK: Chrome (header + footer)

    enum Chrome {
        /// Horizontal inset for the top controls row (video mode, EV, lock, format).
        static let headerHorizontalPadding: CGFloat = 16

        /// Shared circular icon button diameter for footer controls.
        static let footerIconSize: CGFloat = 44
    }

    // MARK: Record Cluster

    enum RecordCluster {
        /// Diameter of the record button hit target.
        static let buttonDiameter: CGFloat = 72
    }

    // MARK: Teleprompter

    enum Teleprompter {
        /// Viewport length (clamped to the preview height at runtime).
        static let viewportHeight: CGFloat = 475

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
        static let width: CGFloat = 44

        /// Height — matched to RecordingClusterView intrinsic height.
        static let height: CGFloat = 156
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
/// After the VStack/HStack refactor, most absolute-position anchors are
/// gone. This struct now provides the preview size (used for teleprompter
/// viewport clamping) and safe-area passthrough.
struct CameraScreenLayout {

    // MARK: Feature Sub-anchors

    struct PreviewAnchors {
        let size: CGSize
    }

    struct SafeAreaAnchors {
        let topInset: CGFloat
        let bottomInset: CGFloat
    }

    // MARK: Outputs

    let preview: PreviewAnchors
    let safeArea: SafeAreaAnchors

    // MARK: Init

    init(containerSize: CGSize, safeAreaInsets: EdgeInsets) {
        // Preview
        let frame = CameraLayout.previewFrame(containerSize: containerSize)
        let previewSize = CGSize(
            width: containerSize.width,
            height: frame.previewHeight
        )

        self.preview = PreviewAnchors(
            size: previewSize
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

