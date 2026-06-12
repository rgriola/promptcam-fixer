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
import PhotosUI
import SwiftUI

/// Primary camera surface that composes preview, teleprompter, and control chrome.
struct CameraView: View {
    /// View model that owns camera state, routes, and actions.
    @State var viewModel: CameraViewModel
    /// Maximum absolute EV value used by focus/exposure drag calculations.
    private let exposureRange: Float = 5.0

    // MARK: - Focus / Exposure Gesture State
    /// Current focus indicator center in preview coordinates.
    @State private var focusIndicatorPoint: CGPoint?
    /// Controls visibility of the focus indicator.
    @State private var showFocusIndicator = false
    /// Work item used to hide focus indicator after inactivity.
    @State private var hideFocusWorkItem: DispatchWorkItem?
    /// Current EV value shown in UI and bound to the EV panel slider.
    @State private var exposureBias: Float = 0

    // MARK: - Sheet / Picker State
    /// Temporary media selection binding for PhotosPicker.
    @State private var selectedMediaItem: PhotosPickerItem?

    // MARK: - Teleprompter State
    /// Script text we last auto-centered for. Re-center whenever the text changes.
    @State private var lastCenteredScriptText: String?
    /// Controls visibility of the teleprompter adjustment panel.
    @State private var showAdjustmentPanel: Bool = false
    
    // MARK: - EV Panel State
    /// Controls visibility of the EV adjustment panel.
    @State private var showEVPanel: Bool = false
    
    // MARK: - Instructions Sheet State
    /// Controls visibility of the instructions guide sheet.
    @State private var showInstructions: Bool = false

    // MARK: - Body

    var body: some View {
        @Bindable var viewModel = viewModel
        return GeometryReader { proxy in
            // Shared geometry values for safe-area-aware camera composition.
            let (barHeight, previewHeight) = CameraLayout.barHeights(containerSize: proxy.size)

            let previewCenter = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let previewTopY = previewCenter.y - (previewHeight / 2)
            let previewBottomY = previewCenter.y + (previewHeight / 2)

            // Clamps prompter viewport height to a specic range. Max returns the larger of the two values. Min returns the smaller of the two values.
            let teleprompterViewportHeight = min(max(CameraLayout.teleprompterViewportHeight, 0), previewHeight)

            let minTeleprompterCenterY = previewTopY + (teleprompterViewportHeight / 2)
            let maxTeleprompterCenterY = previewBottomY - (teleprompterViewportHeight / 2)

            let requestedTeleprompterCenterY = previewBottomY - CameraLayout.teleprompterBottomInset - (teleprompterViewportHeight / 2)

            let teleprompterCenterY = min(max(requestedTeleprompterCenterY, minTeleprompterCenterY), maxTeleprompterCenterY)

            // should set the location of the Teleprompter Center Reset
            let resetTeleprompterBottomY = proxy.size.height - CameraLayout.teleprompterBottomInset

            let teleprompterResetX = previewCenter.x + (proxy.size.width / 2) - CameraLayout.teleprompterResetEdgeInset

            let safeTopInset = proxy.safeAreaInsets.top
            let safeBottomInset = proxy.safeAreaInsets.bottom

            ZStack {
                // Layer 1: Live camera preview with tap gesture (long-press removed - conflicts with teleprompter).
                CameraPreviewView(
                    session: viewModel.session,
                    onTap: { devicePoint, viewPoint in
                        handlePreviewTap(devicePoint: devicePoint, viewPoint: viewPoint, barHeight: barHeight)
                    }
                )
                .frame(width: proxy.size.width, height: previewHeight)
                .position(previewCenter)

                // Layer 2: Focus reticle + EV drag layer shown after tap/long-press.
                if showFocusIndicator, let focusIndicatorPoint {
                    FocusIndicatorView(
                        showFocusIndicator: showFocusIndicator
                    )
                    .position(focusIndicatorPoint)
                }

                // Layer 3: Header, record cluster, and footer chrome.
                VStack(spacing: 0) {
                    cameraHeader()
                    .frame(height: safeTopInset, alignment: .top)

                    Spacer(minLength: 0)

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
                    .padding(.bottom, CameraLayout.recordingBottomPadding)

                   cameraFooter()
                        //.frame(height: barHeight + safeBottomInset, alignment: .bottom)
                       // .frame(height: safeBottomInset, alignment: .bottom)
                       .frame(height: barHeight + safeBottomInset, alignment: .bottom)
                       .offset(y: CameraLayout.footerVerticalOffset)

                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                .frame(width: proxy.size.width, height: teleprompterViewportHeight)
                .position(x: previewCenter.x, y: teleprompterCenterY)

                // Layer 5: Mid-screen reset button.
                TeleprompterCenterResetButton(
                    isDisabled: viewModel.isRecording,
                    action: {
                        viewModel.resetTeleprompterPosition()
                    }
                )
                .frame(width: CameraLayout.teleprompterResetButtonSize,
                       height: CameraLayout.teleprompterResetButtonSize)
               // .position(x: teleprompterResetX, y: teleprompterCenterY)
               .position(x: teleprompterResetX, y: resetTeleprompterBottomY)

                // Layer 6: Teleprompter adjustment panel — slides up from below viewport.
                if showAdjustmentPanel {
                    VStack {
                        // Tap-off-screen dismiss area — covers everything above the panel.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showAdjustmentPanel = false
                                }
                                Log.ui.debug("adjustmentPanel dismissed via tap-outside")
                            }
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
                            }
                        )
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Layer 7: Temporary warning banner (top center).
                TemporaryWarningBanner(
                    message: "Stop recording to change format.",
                    systemImage: "exclamationmark.triangle.fill",
                    autoDismissAfter: 3.0,
                    isPresented: $viewModel.showFormatLockedWarning
                )
                
                // Layer 8: EV adjustment panel — slides down from EV button.
                if showEVPanel {
                    VStack(spacing: 0) {
                        // Panel container aligned to top-leading (below EV button)
                        HStack {
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
                                }
                            )
                            .frame(width: 240)
                            .padding(.top, safeTopInset + Theme.space8)
                            .padding(.leading, Theme.space12)
                            
                            Spacer()
                        }
                        
                        Spacer()
                        
                        // Tap-off-screen dismiss area
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showEVPanel = false
                                }
                                Log.ui.debug("EV panel dismissed via tap-outside")
                            }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(Theme.bgGrad) // background for main view ZStack
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // MARK: - Alerts & Pickers
        .alert("Error", isPresented: Binding(get: {
            viewModel.errorMessage != nil
        }, set: { _ in
            viewModel.errorMessage = nil
        })) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .photosPicker(
            isPresented: $viewModel.isPhotoPickerPresented,
            selection: $selectedMediaItem,
            matching: .videos,
            preferredItemEncoding: .automatic
        )
        .sheet(item: $viewModel.activeSheet) { route in
            sheetContent(for: route)
        }
        .sheet(isPresented: $showInstructions) {
            InstructionsView()
        }
        // MARK: - Lifecycle
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
            viewModel.unlockFocusExposure()
            cleanupFocusState()
        }
        // MARK: - State Observers
        .onChange(of: selectedMediaItem) { _, newItem in
            guard newItem != nil else { return }
            Log.ui.info("Media selected from library picker")
            selectedMediaItem = nil
        }
        .onChange(of: viewModel.activeSheet) { _, newValue in
            viewModel.handleSheetStateChanged(newValue)
        }
        .onChange(of: viewModel.isPhotoPickerPresented) { _, newValue in
            viewModel.handlePhotoPickerStateChanged(newValue)
        }
        .onChange(of: viewModel.lockStatus) { _, newStatus in
            // Simplified: locked states keep reticle visible, unlocked states auto-hide.
            if newStatus.isLocked {
                showFocusIndicator = true
                hideFocusWorkItem?.cancel()
                hideFocusWorkItem = nil
            } else {
                scheduleFocusHide()
            }
        }
    }

    // MARK: - Header & Footer Builders

    /// Builds the top camera controls row and format quick panel.
    /// - Parameter safeTopInset: Safe-area inset used to anchor controls below the notch.
    /// - Returns: Configured top controls view.
    private func cameraHeader() -> some View {
        let evValue = min(max(exposureBias, -exposureRange), exposureRange)
        let evText = String(format: "%.1f", evValue)

        return CameraTopControlsView(
            evText: evText,
            lockStatus: viewModel.lockStatus,
            resolutionLabel: viewModel.recordingFormat.resolution.rawValue,
            fpsLabel: viewModel.recordingFormat.frameRate.displayLabel,
            onTapEV: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showEVPanel.toggle()
                    // Close teleprompter panel if open (mutual exclusion)
                    if showEVPanel {
                        showAdjustmentPanel = false
                    }
                }
                Log.ui.debug("EV panel toggled -> \(showEVPanel, privacy: .public)")
            },
            onTapGrid: {
                showInstructions = true
                Log.ui.debug("Instructions sheet opened")
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showAdjustmentPanel.toggle()
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
    private func handlePreviewTap(devicePoint: CGPoint, viewPoint: CGPoint, barHeight: CGFloat) {
        viewModel.focus(at: devicePoint)
        Log.ui.debug("Touch Focus at point")
        updateFocusIndicatorPosition(viewPoint: viewPoint, barHeight: barHeight)
        scheduleFocusHide()
    }

    /// Positions and shows the focus indicator using preview touch coordinates.
    private func updateFocusIndicatorPosition(viewPoint: CGPoint, barHeight: CGFloat) {
        withAnimation(.easeOut(duration: 0.15)) {
            focusIndicatorPoint = CGPoint(x: viewPoint.x, y: viewPoint.y + barHeight)
            showFocusIndicator = true
        }
    }

    /// Schedules reticle fade-out for non-locked focus states.
    private func scheduleFocusHide() {
        guard !viewModel.lockStatus.isLocked else { return }

        hideFocusWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 1.15)) {
                showFocusIndicator = false
            }
        }

        hideFocusWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
    
    // MARK: - Lock Toggle Helpers
    
    /// Toggles AF/AE lock on/off. When locking, uses the last focus point
    /// if available, otherwise uses screen center.
    private func toggleLockStatus() {
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
    
    /// Cancels pending focus/exposure work items on view disappearance.
    private func cleanupFocusState() {
        hideFocusWorkItem?.cancel()
        hideFocusWorkItem = nil
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
                supportedResolutions: viewModel.supportedResolutions,
                supportedFrameRates: viewModel.supportedFrameRates,
                isRecording: viewModel.isRecording,
                onFormatChanged: { format in
                    viewModel.updateRecordingFormat(format)
                },
                onClose: {
                    viewModel.dismissActiveSheet()
                }
            )
        case .composeScript:
            ComposeScriptSheet(
                initialText: viewModel.config.text,
                onSave: { text in
                    viewModel.updateScriptText(text)
                    viewModel.dismissActiveSheet()
                },
                onCancel: {
                    viewModel.dismissActiveSheet()
                }
            )
        case .settings:
            CameraSettingsSheet {
                viewModel.dismissActiveSheet()
            }
        }
    }
}
