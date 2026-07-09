// PromptCam — Recording Cluster (Record + Scroll Controls)
// Extracted from CameraView.swift (refactor June 1, 2026)
// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add AlignmentToggleButton
// July 8, 2026 - GitHub Copilot (Claude Opus 4.7) - AlignmentToggleButton styling matches TeleprompterCenterResetButton
import SwiftUI

// MARK: - Center Record Cluster

/// Native-like stacked record + scroll control cluster positioned
/// between the header and footer chrome. The record button is centered
/// with the scroll toggle offset to the right and alignment toggle to the left.
struct RecordingClusterView: View {
    /// Whether capture is currently recording.
    let isRecording: Bool
    /// Whether teleprompter auto-scroll is currently active.
    let isScrolling: Bool
    /// Enables/disables record interaction based on camera readiness.
    let isRecordEnabled: Bool
    /// Current text alignment state.
    let textAlignment: TeleprompterTextAlignment
    /// Action to start/stop recording.
    let onRecordTap: () -> Void
    /// Action to pause/play teleprompter scrolling.
    let onScrollTap: () -> Void
    /// Action to cycle through text alignment options.
    let onAlignmentTap: () -> Void

    /// Native-like stacked record + scroll control cluster.
    var body: some View {
        ZStack {
            RecordButton(
                isRecording: isRecording,
                isEnabled: isRecordEnabled,
                action: onRecordTap)

            ScrollToggleButton(
                isScrolling: isScrolling,
                isEnabled: true,
                action: onScrollTap
            )
            .offset(y: -80)

            AlignmentToggleButton(
                alignment: textAlignment,
                isEnabled: !isRecording,
                action: onAlignmentTap
            )
            .offset(x: 165, y: -40)
        }
    }
}

// MARK: - Record Button
/// Primary shutter control used for start/stop recording.
/// Shows a red circle when idle and a white stop-square when recording.
struct RecordButton: View {
    /// Whether recording is currently active.
    let isRecording: Bool
    /// Whether the button should accept taps.
    let isEnabled: Bool
    /// Callback to toggle recording state.
    let action: () -> Void

    /// Primary shutter control used for start/stop recording.
    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: isRecording ? "square.fill" : "circle.fill")
                    .font(Theme.icon34)
                    .foregroundStyle(isRecording ? Theme.white : Theme.red)
                    .padding()
                    .background(
                        Circle()
                            // .fill(isRecording ? Theme.red : Theme.red.opacity(0.5))
                            .fill(Theme.red)
                    )
                    .overlay(
                        Circle().strokeBorder(Theme.white.opacity(0.4), lineWidth: 2)
                    )

            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel(
            isRecording ? "Stop recording" : "Start recording"
        )
        .accessibilityHint("Toggles video recording")
    }
}

// MARK: - Prompter Pause/Play Toggle Button
/// Secondary control to pause/play teleprompter movement.
/// Blue circle with play/pause icon.
struct ScrollToggleButton: View {
    /// Whether teleprompter scrolling is active.
    let isScrolling: Bool
    /// Whether the button should accept taps.
    let isEnabled: Bool
    /// Callback to toggle scroll state.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: isScrolling ? "pause.fill" : "play.fill")
                    .font(Theme.icon34)
                    .foregroundStyle(Theme.white)
                    .padding()
                    .background(
                        Circle()
                            .fill(
                                Theme.blue)
                    )
                    .overlay(
                        Circle().strokeBorder(
                            Theme.white.opacity(0.4), lineWidth: 2)
                    )
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel(isScrolling ? "Pause teleprompter" : "Play teleprompter")
        .accessibilityHint("Toggles teleprompter scrolling")
    }
}

// MARK: - Alignment Toggle Button
/// Tertiary control to cycle through text alignment options.
/// White circle with alignment icon (center/left/right).
struct AlignmentToggleButton: View {
    /// Current text alignment state.
    let alignment: TeleprompterTextAlignment
    /// Whether the button should accept taps.
    let isEnabled: Bool
    /// Callback to advance to next alignment.
    let action: () -> Void

    /// Tertiary control to cycle through text alignment options.
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: alignment.iconName)
                    .font(Theme.icon16)
                    .foregroundStyle(Theme.white)
                Text("Align")
                    .font(Theme.font10Regular)
                    .foregroundStyle(Theme.primaryText)
            }
            .frame(
                width: CameraLayout.teleprompterUtilityButtonWidth,
                height: CameraLayout.teleprompterUtilityButtonHeight
            )
            .roundedBackground()
            .contentShape(
                RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel("Text alignment: \(alignment.rawValue)")
        .accessibilityHint("Cycles between center, left, and right alignment")
    }
}

// MARK: - Component Previews
#Preview("RecordButton - Idle") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        RecordButton(isRecording: false, isEnabled: true) {}
    }
}

#Preview("RecordButton - Recording") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        RecordButton(isRecording: true, isEnabled: true) {}

    }
}

#Preview("ScrollToggleButton - Paused") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        ScrollToggleButton(isScrolling: false, isEnabled: true) {}

    }
}

#Preview("ScrollToggleButton - Scrolling") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        ScrollToggleButton(isScrolling: true, isEnabled: true) {}
    }
}

#Preview("AlignmentToggleButton - Center") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        AlignmentToggleButton(alignment: .center, isEnabled: true) {}

    }
}

#Preview("AlignmentToggleButton - Left") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        AlignmentToggleButton(alignment: .left, isEnabled: true) {}

    }
}

// Note to Agent: This preview is turned off purposely, do not remove as dead code - Rod Griola
/*
#Preview("AlignmentToggleButton - Right") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        AlignmentToggleButton(alignment: .right, isEnabled: true) {}
    }
}
*/
