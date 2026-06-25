// PromptCam — Video Mode Badge
// Created June 14, 2026 - GitHub Copilot
// June 25, 2026 - Merged aperture display into badge for consistent header layout
import SwiftUI

// MARK: - Video Mode Badge

/// Badge displaying the current video mode (Standard or Cinematic),
/// and — when cinematic mode is active and the device supports it —
/// the current simulated aperture as a tappable button inline with the mode label.
///
/// Both elements share the same font and color so they read as a single
/// cohesive header unit regardless of aperture availability.
struct VideoModeBadgeView: View {
    /// Current video mode.
    let mode: VideoMode
    /// Formatted aperture label (e.g. "f/5.6"). Nil when not in cinematic mode
    /// or when the device/OS does not support aperture control (pre-iOS 26).
    var apertureText: String? = nil
    /// Action fired when the user taps the aperture label.
    /// Ignored when `apertureText` is nil.
    var onTapAperture: (() -> Void)? = nil

    // MARK: - Private helpers

    private var modeColor: Color {
        switch mode {
        case .standard:  return Theme.primaryText
        case .cinematic: return Theme.accent
        }
    }

    private var modeText: String {
        switch mode {
        case .standard:  return "STANDARD"
        case .cinematic: return "CINE"
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 6) {
            // Mode label — always visible.
            Text(modeText)
                .font(Theme.mono16Medium)
                .foregroundStyle(modeColor)
                .accessibilityLabel("Video mode")
                .accessibilityValue(mode.displayLabel)

            // Aperture button — only visible in cinematic mode on supported devices.
            if let apertureText, let onTapAperture {
                Button(action: onTapAperture) {
                    Text(apertureText)
                        .font(Theme.mono16Medium)
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Simulated aperture")
                .accessibilityHint("Adjusts depth-of-field blur in cinematic mode")
            }
        }
    }
}
