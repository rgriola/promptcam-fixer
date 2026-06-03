// PromptCam — Footer Controls
// Extracted from CameraView.swift (refactor June 1, 2026)
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
    /// Action to open settings sheet.
    let onTapSettings: () -> Void

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

            footerIconButton(systemName: "gear", action: onTapSettings)
                .accessibilityLabel("Open camera settings")
            
            Spacer()
        }
            .padding(.horizontal, Theme.space12)
            .padding(.bottom, Theme.space8) // Separate from preview.
            .background(Theme.panelBg.opacity(0.9))
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
