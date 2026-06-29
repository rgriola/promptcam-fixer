// PromptCam — Primary Camera Screen
// Refactored June 1, 2026 — sub-views extracted into Views/Camera/ and Views/Sheets/
// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Phase 3: pass TeleprompterConfig object to TeleprompterOverlayView
// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Phase 5: add TeleprompterAdjustmentPanel toggle + persistence
// June 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add EV adjustment panel with hash marks and Auto button
//
// Architecture:
// CameraView is the root composition layer. It owns:
// 1. ZStack layering order: preview → focus reticle → control chrome → teleprompter → reset button
// 2. Focus/exposure gesture state (tap, long-press, EV drag)
// 3. Sheet routing via sheetContent(for:)
//
// Focus/exposure @State lives here (not in ViewModel) because it controls
// view-local animation timing and position — the ViewModel only owns the
// camera-service-facing lock status.
import AVFoundation
import SwiftUI

/// Primary camera surface that composes preview, teleprompter, and control chrome.
struct CameraView: View {
    /// View model that owns camera state, routes, and actions.
    @State var viewModel: CameraViewModel
    /// Maximum absolute EV value used by focus/exposure drag calculations.
    private let exposureRange: Float = 5.0

    /// Current EV value shown in UI and bound to the EV panel slider.
    @State private var exposureBias: Float = 0

    // MARK: - Sheet / Picker State

    // MARK: - Teleprompter State
    /// Script text we last auto-centered for. Re-center whenever the text changes.
    @State private var lastCenteredScriptText: String?
    /// Controls visibility of the teleprompter adjustment panel.
    @State private var showAdjustmentPanel: Bool = false
    
    // MARK: - EV Panel State
    /// Controls visibility of the EV adjustment panel.
    @State private var showEVPanel: Bool = false
    
    // MARK: - Aperture Panel State
    /// Controls visibility of the cinematic aperture panel.
    @State private var showAperturePanel: Bool = false
    
    // MARK: - Body

    var body: some View {
        @Bindable var viewModel = viewModel
        return GeometryReader { proxy in
            let layout = CameraScreenLayout(
                containerSize: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets // pad for notch
            )

            ZStack {
                // Layer 1: Live camera preview, top-anchored and ignoring the top safe area
                // so it extends under the status bar / Dynamic Island.
                CameraPreviewView(
                    session: viewModel.session,
                    onTap: { devicePoint, viewPoint in
                        handlePreviewTap(devicePoint: devicePoint, viewPoint: viewPoint)
                    }
                )
                .frame(width: layout.previewSize.width, height: layout.previewSize.height)
                .position(x: layout.previewCenterX, y: layout.previewTopY + layout.previewSize.height / 2)
                .ignoresSafeArea(.container, edges: .top)
                .ignoresSafeArea(.keyboard) // Prevent keyboard from resizing camera preview

                // Layer 2.5: Audio VU meter on the left edge of the preview.
                // Hidden when any modal sheet is open.

                if viewModel.activeSheet == nil && !viewModel.showComposeSheet {
                    let meterHeight = layout.previewSize.height * 0.28
                    VUMeterView(
                        level: viewModel.audioLevel,
                        peak: viewModel.audioPeak,
                        isExternalMic: viewModel.isExternalMic,
                        isRecording: viewModel.isRecording,
                        level2: viewModel.isStereoInput ? viewModel.audioLevel2 : nil,
                        peak2:  viewModel.isStereoInput ? viewModel.audioPeak2  : nil,
                        sourceNameHint: viewModel.audioSourceHint
                    )
                    .frame(
                        width: CameraLayout.vuMeterWidth,
                        height: meterHeight
                    )
                    .background(
                        Color.black.opacity(0.3)
                        .cornerRadius(8)
                        .padding(-10)
                        )
                    .position(
                        x: CameraLayout.vuMeterHorizontalInset + CameraLayout.vuMeterHorizontalNudge,
                        // Align meter bottom with record-button bottom.
                        y: layout.previewSize.height
                            - CameraLayout.vuMeterBottomOffsetFromPreviewBottom
                            - meterHeight / 2
                    )
                    .transition(.opacity)
                    .onTapGesture {
                        viewModel.openAudioSourcePicker()
                    }
                }

                // Layer 3: Recording cluster positioned at bottom of camera preview
                RecordingClusterView(
                    isRecording: viewModel.isRecording,
                    isScrolling: viewModel.isScrolling,
                    isRecordEnabled: viewModel.isCameraReady,
                    onRecordTap: {
                        viewModel.toggleRecording()
                    },
                    onScrollTap: {
                        viewModel.toggleScrolling()
                    }
                )
                .position(x: proxy.size.width / 2,
                          y: layout.previewSize.height - CameraLayout.recordButtonCenterOffsetFromPreviewBottom)
                
                // Layer 3.5: Recording timer positioned above record button
                RecordingTimerPanel(
                    duration: viewModel.recordingDuration,
                    isRecording: viewModel.isRecording
                )
                .position(x: proxy.size.width / 2,
                          y: layout.previewSize.height - CameraLayout.recordingTimerCenterOffsetFromPreviewBottom)
                
                // Layer 4: Header and footer chrome constrained to space below preview
                VStack(spacing: Theme.space12) {
                    cameraControlsRow()
                    .padding()
                    .background(Theme.black.opacity(0.1))
                    cameraFooter()
                        .padding(.bottom, -10)
                }
                .frame( maxWidth: .infinity, 
                        maxHeight: layout.previewSize.height + CameraLayout.controlChromeMaxHeightExtra,
                        alignment: .bottom)

                // Layer 4: Bottom-anchored teleprompter viewport.
                TeleprompterOverlayView(
                    config: viewModel.config,
                    isScrolling: viewModel.isScrolling,
                    resetToken: viewModel.teleprompterResetToken,
                    onTextHeightChanged: { measuredHeight in 
                        let currentText = viewModel.config.text
                        if lastCenteredScriptText != currentText,
                           measuredHeight > 0 {
                            viewModel.resetTeleprompterPosition()
                            lastCenteredScriptText = currentText
                        }
                    }
                )
                .frame(width: layout.previewSize.width, height: layout.teleprompterViewportHeight)
                .ignoresSafeArea(.keyboard) // Prevent keyboard from resizing teleprompter viewport
                .position(  x: layout.teleprompterCenter.x,
                            y: layout.teleprompterCenter.y - CameraLayout.teleprompterCenterTopOffset
                            )

                // Layer 5: Reset button anchored to the bottom edge of the teleprompter viewport.
                TeleprompterCenterResetButton(
                    isDisabled: viewModel.isRecording,
                    action: {
                        viewModel.resetTeleprompterPosition()
                    }
                )
                .frame(width: layout.teleprompterResetButtonSize,
                       height: layout.teleprompterResetButtonSize)
                .position(layout.teleprompterResetCenter)


                // Layer 6: Teleprompter adjustment panel — standardised panel styling.
                if showAdjustmentPanel {
                    StandardPanelOverlay(onDismiss: {
                        showAdjustmentPanel = false
                        Log.ui.debug("adjustmentPanel dismissed via tap-outside")
                    }) {
                        TeleprompterAdjustmentPanel(
                            config: Binding(
                                get: { viewModel.config },
                                set: { viewModel.updateTeleprompterStyle($0) }
                            ),
                            onReset: {
                                viewModel.updateTeleprompterStyle({
                                    var defaults = TeleprompterConfig.default
                                    defaults.text = viewModel.config.text
                                    return defaults
                                }())
                            },
                            onDismiss: {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showAdjustmentPanel = false
                                }
                            }
                        )
                    }
                }
                
                // Layer 8: EV adjustment panel — standardised panel styling.
                if showEVPanel {
                    StandardPanelOverlay(onDismiss: {
                        showEVPanel = false
                        Log.ui.debug("EV panel dismissed via tap-outside")
                    }) {
                        EVAdjustmentPanel(
                            exposureBias: $exposureBias,
                            exposureRange: exposureRange,
                            onReset: {
                                // Set absolute 0 — bypasses delta drift entirely
                                viewModel.setExposure(to: 0)
                                Log.ui.debug("EV reset to 0 (Auto)")
                            },
                            onAdjust: { newBias in
                                // Absolute value — no delta tracking needed
                                viewModel.setExposure(to: newBias)
                            },
                            onDismiss: {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showEVPanel = false
                                }
                            }
                        )
                    }
                }

                // Layer 9: Cinematic aperture panel — standardised panel styling.
                // Only rendered when cinematicApertureRange is non-nil (cinematic + iOS 26+).
                if showAperturePanel, let apertureRange = viewModel.cinematicApertureRange {
                    StandardPanelOverlay(onDismiss: {
                        showAperturePanel = false
                        Log.ui.debug("Aperture panel dismissed via tap-outside")
                    }) {
                        CinematicAperturePanel(
                            aperture: $viewModel.cinematicSimulatedAperture,
                            apertureRange: apertureRange,
                            defaultAperture: apertureRange.lowerBound,  // f/5.6 after clamping
                            onReset: {
                                viewModel.setSimulatedAperture(apertureRange.lowerBound)
                                Log.ui.debug("Aperture reset to default (f/\(apertureRange.lowerBound))")
                            },
                            onAdjust: { value in
                                viewModel.setSimulatedAperture(value)
                            },
                            onDismiss: {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showAperturePanel = false
                                }
                            }
                        )
                    }
                }

                // Layer 7: Temporary warning banner (top center).
                TemporaryWarningBanner(
                    message: "Stop recording to change format.",
                    systemImage: "exclamationmark.triangle.fill",
                    autoDismissAfter: 3.0,
                    isPresented: $viewModel.showFormatLockedWarning
                )

                // Layer 7.5: Audio route changed warning (e.g. mic disconnect
                // during recording). Body text is provided by the view model.
                TemporaryWarningBanner(
                    message: viewModel.audioRouteChangedMessage,
                    systemImage: "mic.slash.fill",
                    autoDismissAfter: 4.0,
                    isPresented: $viewModel.showAudioRouteChangedWarning
                )

                // Layer 7.6: Silence watchdog — sustained dead audio from
                // an external mic (flaky cable, hardware mute, etc.).
                TemporaryWarningBanner(
                    message: "No audio signal detected. Check microphone connection.",
                    systemImage: "waveform.badge.exclamationmark",
                    autoDismissAfter: 6.0,
                    isPresented: $viewModel.showAudioSilenceWarning
                )

                // Layer 10: Audio source picker — dims 10% and shows input
                // choice when a mic is plugged in or removed.
                if viewModel.showAudioSourcePicker {
                    StandardPanelOverlay(onDismiss: {
                        viewModel.showAudioSourcePicker = false
                    }) {
                        AudioSourcePickerView(
                            inputs: viewModel.availableAudioInputs,
                            activeInputName: viewModel.activeAudioInputName,
                            onSelect: { port in
                                withAnimation(.easeOut(duration: 0.25)) {
                                    viewModel.selectAudioInput(port)
                                }
                            },
                            onDismiss: {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    viewModel.showAudioSourcePicker = false
                                }
                            }
                        )
                    }
                }

            }
            .background(Theme.bgGrad) // background for main view ZStack
            .ignoresSafeArea(.keyboard) // Prevent keyboard from affecting camera layout
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // MARK: - Alerts & Pickers
        .alert("Error", isPresented: Binding(get: {
            viewModel.cameraError != nil
        }, set: { _ in
            viewModel.cameraError = nil
        })) {
            Button("OK", role: .cancel) {
                viewModel.cameraError = nil
            }
        } message: {
            Text(viewModel.cameraError?.localizedDescription ?? "Unknown error")
        }
        .sheet(item: $viewModel.activeSheet) { route in
            sheetContent(for: route)
        }
        .fullScreenCover(isPresented: $viewModel.showComposeSheet) {
            ComposeScriptSheet(
                initialText: viewModel.config.text,
                onSave: { text in
                    viewModel.updateScriptText(text)
                    viewModel.dismissComposeSheet()
                },
                onCancel: {
                    viewModel.dismissComposeSheet()
                }
            )
        }

        // MARK: - Lifecycle
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
            viewModel.unlockFocusExposure()
        }
        // MARK: - State Observers
        .onChange(of: viewModel.activeSheet) { _, newValue in
            viewModel.handleSheetStateChanged(newValue)
        }
        .onChange(of: viewModel.cinematicApertureRange) { _, newRange in
            // Auto-dismiss aperture panel if cinematic mode is turned off.
            if newRange == nil, showAperturePanel {
                withAnimation(Theme.panelSpring) {
                    showAperturePanel = false
                }
            }
        }
    }

    // MARK: - Controls Row & Footer Builders

    /// Builds the top camera controls row (video mode, format, EV, lock).
    /// - Returns: Configured controls row view.
    private func cameraControlsRow() -> some View {
        let evValue = min(max(exposureBias, -exposureRange), exposureRange)
        let evText = String(format: "%.1f", evValue)

        // Build aperture label when cinematicApertureRange is available.
        let apertureText: String? = viewModel.cinematicApertureRange != nil
            ? String(format: "f/%.1f", viewModel.cinematicSimulatedAperture)
            : nil

        return CameraControlsRowView(
            evText: evText,
            lockStatus: viewModel.lockStatus,
            videoMode: viewModel.recordingFormat.mode,
            apertureText: apertureText,
            resolutionLabel: viewModel.recordingFormat.resolution.rawValue,
            fpsLabel: viewModel.recordingFormat.frameRate.displayLabel,
            onTapEV: {
                withAnimation(Theme.panelSpring) {
                    showEVPanel.toggle()
                    if showEVPanel {
                        showAdjustmentPanel = false
                        showAperturePanel = false
                    }
                }
                Log.ui.debug("EV panel toggled -> \(showEVPanel, privacy: .public)")
            },
            onTapAperture: {
                withAnimation(Theme.panelSpring) {
                    showAperturePanel.toggle()
                    if showAperturePanel {
                        showEVPanel = false
                        showAdjustmentPanel = false
                    }
                }
                Log.ui.debug("Aperture panel toggled -> \(showAperturePanel, privacy: .public)")
            },
            onTapFormat: {
                viewModel.openFormatPanel()
            },
            onTapLock: {
                toggleLockStatus()
            }
        )
    }

    /// Builds footer controls for photo picker, compose, and settings routes.
    /// - Parameter safeBottomInset: Safe-area inset used to align footer above home indicator.
    /// - Returns: Configured footer controls view.
   private func cameraFooter() -> some View {
        CameraFooterControlsView(
            onTapPhotoLibrary: {
                viewModel.openPhotoLibrary()
            },
            onTapScriptAssist: {
                viewModel.openCompose()
            },
            onTapAdjust: {
                withAnimation(Theme.panelSpring) {
                    showAdjustmentPanel.toggle()
                    if showAdjustmentPanel {
                        showEVPanel = false
                        showAperturePanel = false
                    }
                }
                Log.ui.debug("adjustmentPanel toggled -> \(showAdjustmentPanel, privacy: .public)")
            },
            onTapSettings: {
                viewModel.openSettings()
            }
        )
    }

    // MARK: - Focus / Exposure Gesture Handlers

    /// Handles single tap to focus at the touched point.
    private func handlePreviewTap(devicePoint: CGPoint, viewPoint: CGPoint) {
        viewModel.focus(at: devicePoint)
        Log.ui.debug("Touch Focus at point")
    }

    // MARK: - Lock Toggle Helpers
    
    /// Toggles AF/AE lock on/off. When locking, uses the last focus point
    /// if available, otherwise uses screen center.
    /// Cinematic mode only supports continuous autofocus, so lock is disabled.
    private func toggleLockStatus() {
        // Cinematic video requires continuous autofocus — lock not supported
        guard viewModel.recordingFormat.mode != .cinematic else {
            Log.ui.info("AF/AE lock blocked — cinematic mode requires continuous autofocus")
            return
        }
        
        if viewModel.lockStatus.isLocked {
            // Unlock: return to continuous auto
            viewModel.unlockFocusExposure()
            Log.ui.info("AF/AE unlocked via button -> AUTO")
        } else {
            // Lock: lock at last focus point (or center if no prior focus)
            // Note: We use center point (0.5, 0.5) in device coordinates for lock
            viewModel.lockFocusExposure(at: CGPoint(x: 0.5, y: 0.5))
            Log.ui.info("AF/AE lock attempted via button at center")
        }
    }

    // MARK: - Sheet Router

    /// Routes the currently active sheet to its destination content.
    /// - Parameter route: Selected modal route from the view model.
    /// - Returns: Sheet content view for the selected route.
    @ViewBuilder
    private func sheetContent(for route: CameraSheetRoute) -> some View {
        switch route {
        case .formatPanel:
            CameraFormatPanelSheet(
                recordingFormat: viewModel.recordingFormat,
                deviceCapabilities: viewModel.deviceCapabilities,
                isRecording: viewModel.isRecording,
                onFormatChanged: { format in
                    viewModel.updateRecordingFormat(format)
                },
                onClose: {
                    viewModel.dismissActiveSheet()
                }
            )
        case .composeScript:
            // Routed via .fullScreenCover above — this case should not be reached.
            EmptyView()
        case .settings:
            CameraSettingsSheet(capabilities: viewModel.deviceCapabilities) {
                viewModel.dismissActiveSheet()
            }
        case .recordingsLibrary:
            RecordingsLibrarySheet()
        }
    }
}
