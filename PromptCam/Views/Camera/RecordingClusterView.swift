// PromptCam — Recording Cluster (Record + Scroll + Timer)
// Extracted from CameraView.swift (refactor June 1, 2026)
// July 10, 2026 - GitHub Copilot (GPT-5.3-Codex) - Move Align to teleprompter utility stack and colocate timer in cluster
import SwiftUI

// MARK: - Center Record Cluster

/// Native-like stacked record + scroll + timer cluster positioned
/// between the header and footer chrome. The record button is centered
/// with secondary controls offset above it.
struct RecordingClusterView: View {
    /// Whether capture is currently recording.
    let isRecording: Bool
    /// Whether teleprompter auto-scroll is currently active.
    let isScrolling: Bool
    /// Enables/disables record interaction based on camera readiness.
    let isRecordEnabled: Bool
    /// Elapsed recording time in seconds.
    let recordingDuration: TimeInterval
    /// Action to start/stop recording.
    let onRecordTap: () -> Void
    /// Action to pause/play teleprompter scrolling.
    let onScrollTap: () -> Void
    /// Native-like stacked record + scroll + timer cluster.
    var body: some View {
            VStack {
                ScrollToggleButton(
                    isScrolling: isScrolling,
                    isEnabled: true,
                    action: onScrollTap
                )
                
                RecordingTimerPanel(
                    duration: recordingDuration,
                    isRecording: isRecording
                )


                RecordButton(
                    isRecording: isRecording,
                    isEnabled: isRecordEnabled,
                    action: onRecordTap
                )
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
                        Circle().strokeBorder(Theme.white.opacity(0.7), lineWidth: 2)
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
                            Theme.white.opacity(0.7), lineWidth: 2)
                    )
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel(isScrolling ? "Pause teleprompter" : "Play teleprompter")
        .accessibilityHint("Toggles teleprompter scrolling")
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

#Preview("RecordingClusterView") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        RecordingClusterView(
            isRecording: false,
            isScrolling: false,
            isRecordEnabled: true,
            recordingDuration: 42,
            onRecordTap: {},
            onScrollTap: {}
        )
    }
}
