// PromptCam — Video Mode Badge
// Created June 14, 2026 - GitHub Copilot
import SwiftUI

// MARK: - Video Mode Badge

/// Badge displaying the current video mode (Standard or Cinematic).
/// Shows "CINE" in distinctive color when cinematic mode is active.
struct VideoModeBadgeView: View {
    /// Current video mode.
    let mode: VideoMode
    
    /// Color based on mode.
    private var modeColor: Color {
        switch mode {
        case .standard:
            return Theme.primaryText.opacity(0.6)
        case .cinematic:
            return Theme.accent
        }
    }
    
    /// Display text for the mode.
    private var modeText: String {
        switch mode {
        case .standard:
            return "STD"
        case .cinematic:
            return "CINE"
        }
    }
    
    var body: some View {
        Text(modeText)
            .font(Theme.mono16Medium)
            .foregroundStyle(modeColor)
            .accessibilityLabel("Video mode")
            .accessibilityValue(mode.displayLabel)
    }
}
