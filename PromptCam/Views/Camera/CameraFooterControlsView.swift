// PromptCam — Footer Controls
// Extracted from CameraView.swift (refactor June 1, 2026)
// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Phase 5: add onTapAdjust button (camera.metering.none)
import SwiftUI

// MARK: - Bottom Footer Controls

/// Footer control row for media import and utility actions.
/// Contains photo library, compose, and settings icon buttons.
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
    /// Action to open the creator guide.
    let onTapGuide: () -> Void

    /// Footer control row for media import and utility actions.
    var body: some View {
        HStack{
            Spacer()

            footerIconButton(systemName: "photo.on.rectangle", action: onTapPhotoLibrary)
                .accessibilityLabel("Open photo library")

            Spacer()

            footerIconButton(systemName: "sparkle.text.clipboard", action: onTapScriptAssist)
                .accessibilityLabel("Insert generated script")
            
            Spacer()

            footerIconButton(
                systemName: "text.viewfinder", 
                action: onTapAdjust)
                .accessibilityLabel("Teleprompter adjustments")

            Spacer()

            footerIconButton(systemName: "gear", action: onTapSettings)
                .accessibilityLabel("Open camera settings")
            
            Spacer()

            Button(action: onTapGuide) {
                Image(systemName: "service.dog.fill")
                    .scaleEffect(x: -1, y: 1)
                    .font(Theme.icon24)
                    .foregroundStyle(Theme.white)
                    .frame(width: CameraLayout.footerIconSize, height: CameraLayout.footerIconSize)
            }
            .accessibilityLabel("Guide")
            .accessibilityHint("Shows Creator Guide")
            
            Spacer()
        }
            .padding(.horizontal, Theme.space12)
            .padding(.top, Theme.space4) 
            .padding(.bottom, Theme.space8) // Separate from preview.
           // .background(Theme.panelBg.opacity(0.9))
            .frame(maxWidth: .infinity)
    }

    /// Shared circular icon button used by footer controls.
    /// - Parameters:
    ///   - systemName: SF Symbol identifier for the icon.
    ///   - action: Callback fired when the footer icon is tapped.
    /// - Returns: Styled footer icon button.
    private func footerIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Image(systemName: systemName)
                    .font(Theme.icon24)
                    .foregroundStyle(Theme.white)
            }
            .frame(width: CameraLayout.footerIconSize, height: CameraLayout.footerIconSize)
        }
    }
}
