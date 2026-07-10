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
import Photos
import SwiftUI
import UIKit

/// Primary camera surface that composes preview, teleprompter, and control chrome.
struct CameraView: View {
    // View model that owns camera state, routes, and actions.
    @State var viewModel: CameraViewModel
    // Maximum absolute EV value used by focus/exposure drag calculations.
    private let exposureRange: Float = 5.0

    // Current EV value shown in UI and bound to the EV panel slider.
    @State private var exposureBias: Float = 0

    // MARK: - Teleprompter State
    /// Script text we last auto-centered for. Re-center whenever the text changes.
    @State private var lastCenteredScriptText: String?
    // MARK: - Sheet / Picker State
    /// Controls visibility of the teleprompter adjustment panel.
    @State private var showAdjustmentPanel: Bool = false

    // MARK: - EV Panel State
    /// Controls visibility of the EV adjustment panel.
    @State private var showEVPanel: Bool = false

    // MARK: - Aperture Panel State
    /// Controls visibility of the cinematic aperture panel.
    @State private var showAperturePanel: Bool = false

    /// Shared permission service injected from the app root via `\.permissionService`.
    /// A view-local default keeps previews and any unhosted uses working out of the box.
    @Environment(\.permissionService) private var permissionService

    private var runtimeRecoveryMessage: PermissionRecoveryMessage? {
        guard let error = viewModel.cameraError else { return nil }
        return PermissionRecoveryMapper.runtimeRecovery(
            for: error,
            snapshot: permissionService.policySnapshot
        )
    }

    // MARK: - Body

    var body: some View {
        @Bindable var viewModel = viewModel
        return GeometryReader { proxy in
            let layout = CameraScreenLayout(
                containerSize: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets  // pad for notch
            )

            ZStack {

                // MARK: - 1: Chrome Controls
                // Foundation below Camera Preview View
                VStack(spacing: Theme.space12) {
                    cameraControlsRow()
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .background(Theme.black.opacity(0.1))
                    cameraFooter()
                    //  .padding(.bottom)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: layout.preview.size.height + CameraLayout.Chrome.controlHeightExtra,
                    alignment: .bottom)

                // MARK: - 2: Camera Preview View
                // Top-anchored, ignores top safe area extends under DI.
                CameraPreviewView(
                    session: viewModel.session,
                    onTap: { devicePoint, viewPoint in
                        handlePreviewTap(devicePoint: devicePoint, viewPoint: viewPoint)
                    }
                )
                .frame(width: layout.preview.size.width, height: layout.preview.size.height)
                .position(
                    x: layout.preview.centerX,
                    y: layout.preview.topY + layout.preview.size.height / 2
                )
                .ignoresSafeArea(.container, edges: .top)
                .ignoresSafeArea(.keyboard)  // Prevent keyboard from resizing camera preview

                // MARK: - 3: VU meters
                // Hides when any modal sheet is open.

                if viewModel.activeSheet == nil && !viewModel.showComposeSheet {
                    VUMeterView(
                        level: viewModel.audioLevel,
                        peak: viewModel.audioPeak,
                        isExternalMic: viewModel.isExternalMic,
                        isRecording: viewModel.isRecording,
                        level2: viewModel.isStereoInput ? viewModel.audioLevel2 : nil,
                        peak2: viewModel.isStereoInput ? viewModel.audioPeak2 : nil,
                        sourceNameHint: viewModel.audioSourceHint
                    )
                    .frame(
                        width: layout.vuMeter.size.width,
                        height: layout.vuMeter.size.height
                    )
                    .roundedBackground()
                    .position(layout.vuMeter.center)
                    .transition(.opacity)
                    .onTapGesture {
                        viewModel.openAudioSourcePicker()
                    }
                }

                // MARK: - 4: Record cluster bewlow Camera Preview + Teleprompter
                RecordingClusterView(
                    isRecording: viewModel.isRecording,
                    isScrolling: viewModel.isScrolling,
                    isRecordEnabled: viewModel.isCameraReady,
                    recordingDuration: viewModel.recordingDuration,
                    onRecordTap: {
                        viewModel.toggleRecording()
                    },
                    onScrollTap: {
                        viewModel.toggleScrolling()
                    }
                )
                .position(layout.recordCluster.recordButtonCenter)

                  // MARK: - 7: Prompter Utility Stack (Align + Reset)
                TeleprompterUtilityStackView(
                    textAlignment: viewModel.config.textAlignment,
                    isRecording: viewModel.isRecording,
                    onAlignmentTap: {
                        viewModel.cycleTextAlignment()
                    },
                    onResetTap: {
                        viewModel.resetTeleprompterPosition()
                    }
                )
                .position(layout.teleprompter.resetCenter)

                // MARK: - 6: Bottom-anchored teleprompter viewport.
                TeleprompterOverlayView(
                    config: viewModel.config,
                    isScrolling: viewModel.isScrolling,
                    resetToken: viewModel.teleprompterResetToken,
                    onTextHeightChanged: { measuredHeight in
                        let currentText = viewModel.config.text
                        if lastCenteredScriptText != currentText,
                            measuredHeight > 0
                        {
                            viewModel.resetTeleprompterPosition()
                            lastCenteredScriptText = currentText
                        }
                    }
                )
                .frame(width: layout.preview.size.width, height: layout.teleprompter.viewportHeight)
                .ignoresSafeArea(.keyboard)  // Prevent keyboard from resizing teleprompter viewport
                .position(layout.teleprompter.center)

              

                // MARK: - 8: Prompter Control Panel
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
                                viewModel.updateTeleprompterStyle(
                                    {
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

                // MARK: - 9: EV adjustment panel
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

                // MARK: - 10: Cine Aperture
                // Renders if cinematicApertureRange is non-nil (cinematic + iOS 26+)
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
                                Log.ui.debug(
                                    "Aperture reset to default (f/\(apertureRange.lowerBound))")
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

                // MARK: - 11: Warn Stop Recording (top center).
                TemporaryWarningBanner(
                    message: "Stop recording to change format.",
                    systemImage: "exclamationmark.triangle.fill",
                    autoDismissAfter: 3.0,
                    isPresented: $viewModel.showFormatLockedWarning
                )

                // MARK: - 12: Warn Audio Changed
                //(e.g. mic disconnectduring recording)
                TemporaryWarningBanner(
                    message: viewModel.audioRouteChangedMessage,
                    systemImage: "mic.slash.fill",
                    autoDismissAfter: 4.0,
                    isPresented: $viewModel.showAudioRouteChangedWarning
                )

                // MARK: - 13: Warn No Audio —
                // sustained dead audio
                TemporaryWarningBanner(
                    message: "No audio signal detected. Check microphone connection.",
                    systemImage: "waveform.badge.exclamationmark",
                    autoDismissAfter: 6.0,
                    isPresented: $viewModel.showAudioSilenceWarning
                )

                // MARK: - 14: Audio Source Picker —
                // Dims 10% givs input options.
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
            .background(Theme.bgGrad)  // background for main view ZStack
            .ignoresSafeArea(.keyboard)  // Prevent keyboard from affecting camera layout
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // MARK: - 15: - Alerts & Pickers
        .alert(
            runtimeRecoveryMessage?.title ?? "Error",
            isPresented: Binding(
                get: {
                    viewModel.cameraError != nil
                },
                set: { _ in
                    viewModel.cameraError = nil
                })
        ) {
            if runtimeRecoveryMessage?.action == .openSettings {
                Button("Open Settings") {
                    openAppSettings()
                    viewModel.cameraError = nil
                }
            }
            Button("OK", role: .cancel) {
                viewModel.cameraError = nil
            }
        } message: {
            Text(
                runtimeRecoveryMessage?.message ?? viewModel.cameraError?.localizedDescription
                    ?? "Unknown error")
        }
        .sheet(item: $viewModel.activeSheet) { route in
            sheetContent(for: route)
        }
        .fullScreenCover(isPresented: $viewModel.showDirectPlayer) {
            if let recording = viewModel.latestRecording {
                RecordingPlayerView(
                    recording: recording,
                    videoURL: viewModel.latestVideoURL,
                    onDelete: {
                        // Delegate to the nonisolated RecordingsService instead
                        // of inlining PHPhotoLibrary.performChanges here. The
                        // Task { } below inherits @MainActor from the enclosing
                        // View body; any closure captured inside it (including
                        // the one PhotoKit passes to its serial changes queue)
                        // gets tagged with MainActor isolation, which trips
                        // Swift 6's executor mismatch check and crashes.
                        // The service method is a nonisolated struct func, so
                        // its internal closures run without MainActor taint.
                        let recordingToDelete = recording
                        Task {
                            _ = await RecordingsService().deleteRecording(recordingToDelete)
                            // Keep player open — user can manually close or select another video
                            viewModel.refreshLatestRecording()
                        }
                    },
                    recentRecordings: viewModel.recentRecordings,
                    thumbnailLoader: { rec in
                        // Visible carousel cell — use .opportunistic so
                        // iCloud-offloaded thumbnails trigger a download and
                        // render as soon as any rep (degraded or full) lands,
                        // instead of returning nil and waiting for the cell's
                        // 3s retry. Pre-warm / cover paths keep .fastFormat.
                        await RecordingsService().thumbnail(
                            for: rec,
                            targetSize: CGSize(width: 144, height: 144),
                            deliveryMode: .opportunistic
                        )
                    },
                    coverThumbnailLoader: { rec in
                        // Cover thumbnail shown during the ~200ms player transition.
                        // Previously requested screenSize × 2x (retina) — for an
                        // iCloud-offloaded video that forced a full-resolution
                        // download just to show a 200ms fade. A 500pt max is
                        // large enough that the transition doesn't look pixelated
                        // when scaled up, and PhotoKit can serve it from a much
                        // cheaper cached representation.
                        return await RecordingsService().thumbnail(
                            for: rec,
                            targetSize: CGSize(width: 500, height: 500)
                        )
                    },
                    resolveURL: { rec in
                        await RecordingsService().resolveURL(for: rec)
                    },
                    resolveURLWithProgress: { rec, reporter, onStart in
                        let result = await RecordingsService().resolveURL(
                            for: rec,
                            progress: { fraction in
                                reporter.report(fraction)
                            },
                            onStart: onStart
                        )
                        return result.url
                    },
                    onSelectRecording: { selected, _ in
                        // Do NOT overwrite viewModel.latestRecording here —
                        // that would make the player reopen on the last-viewed video instead of the most recently recorded one. The RecordingPlayerView tracks its own @State activeRecording for in-session swiping.
                        viewModel.warmCarouselCache(around: selected)
                    }
                )
            }
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

        // MARK: - 15: - Lifecycle
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
        .onChange(of: viewModel.isRecording) { _, isRecording in
            // Auto-dismiss open panels when recording starts so they don't
            // appear in the captured video or block the recording chrome.
            if isRecording {
                withAnimation(Theme.panelSpring) {
                    showEVPanel = false
                    showAperturePanel = false
                    showAdjustmentPanel = false
                }
            }
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

    private func openAppSettings() {
        PermissionAnalyticsService.trackOpenSettingsTapped(
            permission: runtimePermissionType,
            sourceSurface: .runtimeAlert,
            snapshot: permissionService.policySnapshot
        )
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var runtimePermissionType: PermissionAnalyticsPermission {
        let snapshot = permissionService.policySnapshot
        if snapshot.camera == .denied || snapshot.camera == .restricted { return .camera }
        if snapshot.microphone == .denied || snapshot.microphone == .restricted {
            return .microphone
        }
        if snapshot.photoLibrary == .denied || snapshot.photoLibrary == .restricted {
            return .photoLibrary
        }
        return .unknown
    }

    // MARK: Top Row Build
    // Camera Mode, format, EV, lock Controls
    private func cameraControlsRow() -> some View {
        let evValue = min(max(exposureBias, -exposureRange), exposureRange)
        let evText = String(format: "%.1f", evValue)

        // Build aperture label when cinematicApertureRange is available.
        let apertureText: String? =
            viewModel.cinematicApertureRange != nil
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
            },
            isRecording: viewModel.isRecording
        )
    }

    // MARK: Footer Build
    // Buttons; photo picker, script, prompter controils, settings routes.
    // Returns: Configured footer controls view.
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
            },
            isRecording: viewModel.isRecording,
            // Drives the LibraryThumbnailButton's `.task(id:)` so its thumbnail
            // reloads whenever the latest recording changes (new save, delete,
            // iCloud sync). `refreshLatestRecording()` in CameraViewModel is
            // already wired to PhotoLibraryChangeMonitor, so this stays in
            // sync automatically without adding another observer here.
            latestRecordingID: viewModel.latestRecording?.id
        )
    }

    // MARK: - Focus / Exposure Gesture Handlers

    /// Handles single tap to focus at the touched point.
    /// No-op while recording to prevent accidental refocus mid-take.
    private func handlePreviewTap(devicePoint: CGPoint, viewPoint: CGPoint) {
        guard !viewModel.isRecording else { return }
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
