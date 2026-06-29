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

    // MARK: - Body

    var body: some View {
        HStack(spacing: 5) {
            // Camera icon — always visible, color reflects current mode.
            Image(systemName: "video.fill")
                .font(Theme.mono16Medium)
                .foregroundStyle(modeColor)
                .accessibilityLabel("Video mode")
                .accessibilityValue(mode.displayLabel)

            // Mode suffix: "REG" for standard, "C" + aperture for cinematic.
            if mode == .standard {
                Text("REG")
                    .font(Theme.mono16Medium)
                    .foregroundStyle(Theme.primaryText)
            } else {
                Text("C")
                    .font(Theme.mono16Medium)
                    .foregroundStyle(Theme.accent)

                // Aperture button — only on supported devices (iOS 26+).
                if let apertureText, let onTapAperture {
                    Button(action: onTapAperture) {
                        Text(apertureText)
                            .font(Theme.mono16Medium)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Simulated aperture")
                    .accessibilityHint("Adjusts depth-of-field blur in cinematic mode")
                }
            }
        }
    }
}
