// PromptCam — Recording Cluster (Record + Scroll Controls)
// Extracted from CameraView.swift (refactor June 1, 2026)
import SwiftUI

// MARK: - Center Record Cluster

/// Native-like stacked record + scroll control cluster positioned
/// between the header and footer chrome. The record button is centered
/// with the scroll toggle offset to the right.
struct RecordingClusterView: View {
    /// Whether capture is currently recording.
    let isRecording: Bool
    /// Whether teleprompter auto-scroll is currently active.
    let isScrolling: Bool
    /// Enables/disables record interaction based on camera readiness.
    let isRecordEnabled: Bool
    /// Action to start/stop recording.
    let onRecordTap: () -> Void
    /// Action to pause/play teleprompter scrolling.
    let onScrollTap: () -> Void

    /// Native-like stacked record + scroll control cluster.
    var body: some View {
        ZStack {
            RecordButton(isRecording: isRecording, isEnabled: isRecordEnabled, action: onRecordTap)
                .frame(width: 72, height: 72)

            ScrollToggleButton(isScrolling: isScrolling, action: onScrollTap)
                .frame(width: 40, height: 40)
                .offset(x: 72)
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
                Circle().fill(
                    isRecording ? Theme.redRecordPreview : Theme.red)
                Circle().strokeBorder(Theme.white, lineWidth: 2)

                if isRecording {
                    Image(systemName: "square.fill")
                        .font(Theme.icon28)
                        .foregroundStyle(Theme.white)
                }
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(
            isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint("Toggles video recording")
    }
}

// MARK: - Scroll Toggle Button

/// Secondary control to pause/play teleprompter movement.
/// Blue circle with play/pause icon.
struct ScrollToggleButton: View {
    /// Whether teleprompter scrolling is active.
    let isScrolling: Bool
    /// Callback to toggle scroll state.
    let action: () -> Void

    /// Secondary control to pause/play teleprompter movement.
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Theme.white, lineWidth: 4)
                Circle().fill(isScrolling ? Theme.blueScrollPreview : Theme.blue)
                Image(systemName: isScrolling ? "pause.fill" : "play.fill")
                    .font(Theme.icon12)
                    .foregroundStyle(Theme.white)
            }
        }
        .accessibilityLabel(isScrolling ? "Pause teleprompter" : "Play teleprompter")
        .accessibilityHint("Toggles teleprompter scrolling")
    }
}

// MARK: - Component Previews

#Preview("RecordButton - Idle") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        RecordButton(isRecording: false, isEnabled: true) {}
            .frame(width: 72, height: 72)
    }
}

#Preview("RecordButton - Recording") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        RecordButton(isRecording: true, isEnabled: true) {}
            .frame(width: 72, height: 72)
    }
}

#Preview("ScrollToggleButton - Paused") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        ScrollToggleButton(isScrolling: false) {}
            .frame(width: 40, height: 40)
    }
}

#Preview("ScrollToggleButton - Scrolling") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        ScrollToggleButton(isScrolling: true) {}
            .frame(width: 40, height: 40)
    }
}
