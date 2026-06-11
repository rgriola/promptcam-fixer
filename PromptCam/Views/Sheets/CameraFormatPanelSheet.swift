// PromptCam — Format Panel Sheet
// Extracted from CameraView.swift (refactor June 1, 2026)
import SwiftUI

// MARK: - Format Sheet

/// Modal sheet for selecting video resolution and frame rate.
/// Pickers are disabled while recording is active.
struct CameraFormatPanelSheet: View {
    /// Current recording format (read from ViewModel).
    let recordingFormat: RecordingFormat
    /// Hardware-supported resolutions for the active camera.
    let supportedResolutions: [VideoResolution]
    /// Hardware-supported frame rates for the active camera.
    let supportedFrameRates: [VideoFrameRate]
    /// Whether the camera is currently recording (disables changes).
    let isRecording: Bool
    /// Callback fired when the user selects a new format.
    let onFormatChanged: (RecordingFormat) -> Void
    /// Callback to dismiss the format sheet.
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Resolution", selection: Binding(
                        get: { recordingFormat.resolution },
                        set: { newRes in
                            onFormatChanged(RecordingFormat(resolution: newRes, frameRate: recordingFormat.frameRate))
                        }
                    )) {
                        ForEach(supportedResolutions, id: \.self) { res in
                            Text(res.rawValue).tag(res)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRecording)
                } header: {
                    Text("Resolution")
                        .foregroundStyle(Theme.primaryText)
                }

                Section {
                    Picker("Frame Rate", selection: Binding(
                        get: { recordingFormat.frameRate },
                        set: { newFPS in
                            onFormatChanged(RecordingFormat(resolution: recordingFormat.resolution, frameRate: newFPS))
                        }
                    )) {
                        ForEach(supportedFrameRates, id: \.self) { rate in
                            Text("\(rate.rawValue) FPS").tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRecording)
                } header: {
                    Text("Frame Rate")
                        .foregroundStyle(Theme.primaryText)
                }

                if isRecording {
                    Section {
                        Label("Stop recording to change format.", systemImage: "exclamationmark.triangle")
                            .font(Theme.font12Regular)
                            .foregroundStyle(Theme.primaryText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("X", action: onClose)
                }
            }
        }
        .presentationBackground(Theme.bgGrad)
    }
}
