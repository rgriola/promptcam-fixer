// PromptCam — Format Panel Sheet
// Extracted from CameraView.swift (refactor June 1, 2026)
import SwiftUI

// MARK: - Format Sheet

/// Modal sheet for selecting video mode, resolution, and frame rate.
/// Pickers are disabled while recording is active.
/// Options are dynamically enabled/disabled based on device capabilities and selected mode.
struct CameraFormatPanelSheet: View {
    /// Current recording format (read from ViewModel).
    let recordingFormat: RecordingFormat
    /// Device capabilities (mode support, resolution/fps per mode).
    let deviceCapabilities: DeviceCapabilities
    /// Whether the camera is currently recording (disables changes).
    let isRecording: Bool
    /// Callback fired when the user selects a new format.
    let onFormatChanged: (RecordingFormat) -> Void
    /// Callback to dismiss the format sheet.
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Video Mode Section
                
                Section {
                    Picker("Mode", selection: Binding(
                        get: { recordingFormat.mode },
                        set: { newMode in
                            // Auto-adjust format when mode changes to ensure valid combination.
                            let tentative = RecordingFormat(
                                resolution: recordingFormat.resolution,
                                frameRate: recordingFormat.frameRate,
                                mode: newMode
                            )
                            let adjusted = deviceCapabilities.adjusted(tentative)
                            onFormatChanged(adjusted)
                        }
                    )) {
                        ForEach(VideoMode.allCases, id: \.self) { mode in
                            Text(mode.displayLabel)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRecording || !deviceCapabilities.supportsCinematicMode)
                } header: {
                    Text("Video Mode")
                        .foregroundStyle(Theme.primaryText)
                } footer: {
                    if recordingFormat.mode == .cinematic {
                        Text("Cinematic mode captures depth data for portrait-style focus effects and requires specific hardware support.")
                            .font(Theme.font12Regular)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("Standard mode provides maximum flexibility for resolution and frame rate.")
                            .font(Theme.font12Regular)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                
                // MARK: - Resolution Section
                
                Section {
                    let validResolutions = deviceCapabilities.resolutions(for: recordingFormat.mode)
                    
                    Picker("Resolution", selection: Binding(
                        get: { recordingFormat.resolution },
                        set: { newRes in
                            onFormatChanged(RecordingFormat(
                                resolution: newRes,
                                frameRate: recordingFormat.frameRate,
                                mode: recordingFormat.mode
                            ))
                        }
                    )) {
                        ForEach(VideoResolution.allCases, id: \.self) { res in
                            Text(res.rawValue)
                                .tag(res)
                                .disabled(!validResolutions.contains(res))
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRecording)
                } header: {
                    Text("Resolution")
                        .foregroundStyle(Theme.primaryText)
                }

                // MARK: - Frame Rate Section
                
                Section {
                    let validFrameRates = deviceCapabilities.frameRates(for: recordingFormat.mode)
                    
                    Picker("Frame Rate", selection: Binding(
                        get: { recordingFormat.frameRate },
                        set: { newFPS in
                            onFormatChanged(RecordingFormat(
                                resolution: recordingFormat.resolution,
                                frameRate: newFPS,
                                mode: recordingFormat.mode
                            ))
                        }
                    )) {
                        ForEach(VideoFrameRate.allCases, id: \.self) { rate in
                            Text("\(rate.rawValue) FPS")
                                .tag(rate)
                                .disabled(!validFrameRates.contains(rate))
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
                
                if !deviceCapabilities.supportsCinematicMode {
                    Section {
                        Label("Cinematic mode is not supported on this device.", systemImage: "info.circle")
                            .font(Theme.font12Regular)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                  //  CloseToolbarButton(action: "Done") { onClose() }

                  CloseToolbarButton { onClose() }
                }
            }
        }
        .presentationBackground(Theme.bgGrad)
    }
}
