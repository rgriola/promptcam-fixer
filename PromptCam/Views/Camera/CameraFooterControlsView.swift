// PromptCam — Footer Controls
// Extracted from CameraView.swift (refactor June 1, 2026)
// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Phase 5: add onTapAdjust button (camera.metering.none)
// June 25, 2026 - Library button now shows circular thumbnail of last saved video (iOS Camera style)
import Photos
import SwiftUI

// MARK: - Bottom Footer Controls

/// Footer control row for media import and utility actions.
/// Contains photo library thumbnail, compose, teleprompter adjust, settings, and guide buttons.
struct CameraFooterControlsView: View {
    /// Device safe-area bottom inset for home-indicator spacing.
   // let safeBottomInset: CGFloat
    /// Action to open PhotosPicker.
    let onTapPhotoLibrary: () -> Void
    /// Action to open compose sheet.
    let onTapScriptAssist: () -> Void
    /// Action to toggle the teleprompter adjustment panel.
    let onTapAdjust: () -> Void
    /// Action to open settings sheet.
    let onTapSettings: () -> Void

    /// Footer control row for media import and utility actions.
    var body: some View {
        HStack(alignment: .top) {
            Spacer()

            // Camera-roll button: circular thumbnail of last recorded video.
            // HStack(alignment: .top) aligns its top edge with the icon tops
            // of the labeled buttons.
            LibraryThumbnailButton(
                size: CameraLayout.footerIconSize,
                action: onTapPhotoLibrary
            )
            .accessibilityLabel("Open photo library")
            .accessibilityHint("Shows your most recently recorded video")

            Spacer()

            footerIconButton(
                systemName: "sparkle.text.clipboard", 
                label: "Script", 
                action: onTapScriptAssist)
                    .accessibilityLabel("Insert generated script")

            Spacer()

            footerIconButton(
                systemName: "text.viewfinder",
                label: "Prompter", action: onTapAdjust
                )
                .accessibilityLabel("Teleprompter adjustments")

            Spacer()

            footerIconButton(
                systemName: "gear",
                label: "Settings", action: onTapSettings
                )
                .accessibilityLabel("Open camera settings")

            Spacer()
        }
        .padding(.horizontal, Theme.space12)
        .padding(.top, Theme.space4)
        .padding(.bottom, Theme.space8)
        .frame(maxWidth: .infinity)
    }

    /// Shared icon + label button used by footer controls.
    private func footerIconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(Theme.icon24)
                    .foregroundStyle(Theme.white)
                    .frame(
                        width: CameraLayout.footerIconSize, 
                        height: CameraLayout.footerIconSize)
                Text(label)
                    .font(Theme.font10Regular)
                    .foregroundStyle(Theme.primaryText)
            }
        }
    }
}

// MARK: - Library Thumbnail Button

/// Circular camera-roll button that shows the most recently saved video thumbnail,
/// mirroring the iOS Camera app's bottom-left library button.
///
/// - Shows a live `aspectFill` thumbnail clipped to a circle with a white border ring.
/// - Falls back to a `photo.on.rectangle` placeholder when no video is available or
///   the photo library permission hasn't been granted yet.
/// - Refreshes every time the view appears via `.task`.
struct LibraryThumbnailButton: View {
    /// Diameter of the circular button — should match `CameraLayout.footerIconSize`.
    let size: CGFloat
    /// Action fired when the button is tapped.
    let action: () -> Void

    @State private var thumbnail: UIImage?
    private let service = RecordingsService()

    var body: some View {
        Button(action: action) {
            if let thumb = thumbnail {
                // Filled thumbnail circle with white border ring.
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.white, lineWidth: 2))
            } else {
                // Placeholder circle while loading or when library is empty/denied.
                Circle()
                    .fill(Theme.white.opacity(0.12))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "photo.on.rectangle")
                            .font(Theme.icon24)
                            .foregroundStyle(Theme.white)
                    )
                    .overlay(Circle().stroke(Theme.white.opacity(0.4), lineWidth: 1.5))
            }
        }
        .task {
            // Target size: 2× pt size for Retina crispness without wasting memory.
            let px = size * 2
            thumbnail = await service.latestVideoThumbnail(
                targetSize: CGSize(width: px, height: px)
            )
        }
    }
}
