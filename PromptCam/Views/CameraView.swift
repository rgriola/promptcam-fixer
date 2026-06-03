// PromptCam — Primary Camera Screen
// Refactored June 1, 2026 — sub-views extracted into Views/Camera/ and Views/Sheets/
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
    @StateObject var viewModel: CameraViewModel
    /// Maximum absolute EV value used by focus/exposure drag calculations.
    private let exposureRange: Float = 5.0

    // MARK: - Focus / Exposure Gesture State

    /// Current focus indicator center in preview coordinates.
    @State private var focusIndicatorPoint: CGPoint?
    /// Controls visibility of the focus indicator.
    @State private var showFocusIndicator = false
    /// Tracks latest EV drag translation to preserve drag baseline state.
    @State private var lastExposureDrag: CGSize = .zero
    /// Work item used to hide focus indicator after inactivity.
    @State private var hideFocusWorkItem: DispatchWorkItem?
    /// Current EV value shown in UI and used for camera exposure updates.
    @State private var exposureBias: Float = 0
    /// Debounces camera exposure writes while dragging EV.
    @State private var exposureDebounceWorkItem: DispatchWorkItem?
    /// EV baseline captured at the start of a drag gesture.
    @State private var exposureDragBaselineBias: Float = 0
    /// Initial Y value captured when EV drag begins.
    @State private var exposureDragBaselineY: CGFloat = 0
    /// Last EV value sent to camera service to compute incremental deltas.
    @State private var lastAppliedExposureBias: Float = 0

    // MARK: - Sheet / Picker State

    /// Temporary media selection binding for PhotosPicker.
    @State private var selectedMediaItem: PhotosPickerItem?

    // MARK: - Teleprompter State

    /// Script text we last auto-centered for. Re-center whenever the text changes.
    @State private var lastCenteredScriptText: String?

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            // Shared geometry values for safe-area-aware camera composition.
            let (barHeight, previewHeight) = CameraLayout.barHeights(containerSize: proxy.size)
            let previewCenter = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let previewTopY = previewCenter.y - (previewHeight / 2)
            let previewBottomY = previewCenter.y + (previewHeight / 2)
            let teleprompterViewportHeight = min(max(CameraLayout.teleprompterViewportHeight, 0), previewHeight)
            let minTeleprompterCenterY = previewTopY + (teleprompterViewportHeight / 2)
            let maxTeleprompterCenterY = previewBottomY - (teleprompterViewportHeight / 2)
            let requestedTeleprompterCenterY = previewBottomY - CameraLayout.teleprompterBottomInset - (teleprompterViewportHeight / 2)
            let teleprompterCenterY = min(max(requestedTeleprompterCenterY, minTeleprompterCenterY), maxTeleprompterCenterY)
            let teleprompterResetX = previewCenter.x + (proxy.size.width / 2) - CameraLayout.teleprompterResetEdgeInset
            let safeTopInset = proxy.safeAreaInsets.top
            let safeBottomInset = proxy.safeAreaInsets.bottom

            ZStack {
                // Layer 1: Live camera preview with tap/long-press gesture hooks.
                CameraPreviewView(
                    session: viewModel.session,
                    onTap: { devicePoint, viewPoint in
                        handlePreviewTap(devicePoint: devicePoint, viewPoint: viewPoint, barHeight: barHeight)
                    },
                    onLongPress: { devicePoint, viewPoint in
                        handlePreviewLongPress(devicePoint: devicePoint, viewPoint: viewPoint, barHeight: barHeight)
                    }
                )
                .frame(width: proxy.size.width, height: previewHeight)
                .position(previewCenter)

                // Layer 2: Focus reticle + EV drag layer shown after tap/long-press.
                if showFocusIndicator, let focusIndicatorPoint {
                    FocusIndicatorView(
                        exposureRange: exposureRange,
                        exposureBias: exposureBias,
                        showFocusIndicator: showFocusIndicator,
                        onDragDelta: { translationHeight in
                            handleExposureDrag(translationHeight: translationHeight)
                        }
                    )
                    .position(focusIndicatorPoint)
                }

                // Layer 3: Header, record cluster, and footer chrome.
                VStack(spacing: 0) {
                    cameraHeader()
                       // .frame(height: barHeight + safeTopInset, alignment: .top)
                       .frame(height: safeTopInset, alignment: .top)

                    Spacer(minLength: 0)

                    RecordingClusterView(
                        isRecording: viewModel.isRecording,
                        isScrolling: viewModel.isScrolling,
                        isRecordEnabled: viewModel.isCameraReady,
                        onRecordTap: {
                            viewModel.toggleRecording()
                            print("Recording toggled")
                        },
                        onScrollTap: {
                            viewModel.toggleScrolling()
                            print("Scroll toggled")
                        }
                    )
                    .padding(.bottom, CameraLayout.recordingBottomPadding)

                    cameraFooter(safeBottomInset: safeBottomInset)
                        .frame(height: barHeight + safeBottomInset, alignment: .bottom)
                        .offset(y: CameraLayout.footerVerticalOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Layer 4: Bottom-anchored teleprompter viewport.
                TeleprompterOverlayView(
                    text: viewModel.config.text,
                    fontSize: viewModel.config.fontSize,
                    speed: viewModel.config.speedPointsPerSecond,
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
                .position(x: teleprompterResetX, y: teleprompterCenterY)
            }
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
        // MARK: - Lifecycle
        .onAppear { viewModel.onAppear() }
        .onDisappear {
            viewModel.onDisappear()
            viewModel.unlockFocusExposure()
            cleanupFocusState()
        }
        // MARK: - State Observers
        .onChange(of: selectedMediaItem) { _, newItem in
            guard newItem != nil else { return }
            print("Media selected from library picker")
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
                print("EV button tapped")
            },
            onTapGrid: {
                print("Grid button tapped")
            },
            onTapFormat: {
                viewModel.openFormatPanel()
            }
        )
    }

    /// Builds footer controls for photo picker, compose, and settings routes.
    /// - Parameter safeBottomInset: Safe-area inset used to align footer above home indicator.
    /// - Returns: Configured footer controls view.
    private func cameraFooter(safeBottomInset: CGFloat) -> some View {
        CameraFooterControlsView(
            safeBottomInset: safeBottomInset,
            onTapPhotoLibrary: {
                viewModel.openPhotoLibrary()
            },
            onTapScriptAssist: {
                viewModel.openCompose()
            },
            onTapSettings: {
                viewModel.openSettings()
            }
        )
    }

    // MARK: - Focus / Exposure Gesture Handlers

    /// Handles single tap to focus and return to auto lock mode when needed.
    private func handlePreviewTap(devicePoint: CGPoint, viewPoint: CGPoint, barHeight: CGFloat) {
        if viewModel.lockStatus != .auto {
            viewModel.unlockFocusExposure()
            print("AE/AF lock released")
        }

        viewModel.focus(at: devicePoint)
        print("Touch Focus")
        updateFocusIndicatorPosition(viewPoint: viewPoint, barHeight: barHeight)
        scheduleFocusHide()
    }

    /// Handles long press to attempt lock behavior at the touched camera point.
    private func handlePreviewLongPress(devicePoint: CGPoint, viewPoint: CGPoint, barHeight: CGFloat) {
        print("Preview long press lock attempt")
        updateFocusIndicatorPosition(viewPoint: viewPoint, barHeight: barHeight)
        viewModel.lockFocusExposure(at: devicePoint)
        scheduleFocusHide()
    }

    /// Positions and shows the focus indicator using preview touch coordinates.
    private func updateFocusIndicatorPosition(viewPoint: CGPoint, barHeight: CGFloat) {
        withAnimation(.easeOut(duration: 0.15)) {
            focusIndicatorPoint = CGPoint(x: viewPoint.x, y: viewPoint.y + barHeight)
            showFocusIndicator = true
        }
    }

    /// Processes EV drag gesture translation into exposure bias updates.
    private func handleExposureDrag(translationHeight: CGFloat) {
        if lastExposureDrag == .zero {
            exposureDragBaselineBias = exposureBias
            exposureDragBaselineY = translationHeight
            lastAppliedExposureBias = exposureBias
        }

        let totalDeltaY = translationHeight - exposureDragBaselineY
        let scalePerPoint: Float = (exposureRange * 2) / Float(CameraLayout.evFullRangePoints)
        let newBias = min(max(exposureDragBaselineBias - Float(totalDeltaY) * scalePerPoint, -exposureRange), exposureRange)

        exposureBias = newBias
        showFocusIndicator = true
        scheduleFocusHide()

        let pending = newBias - lastAppliedExposureBias
        exposureDebounceWorkItem?.cancel()
        let work = DispatchWorkItem {
            viewModel.adjustExposure(by: pending)
            lastAppliedExposureBias = newBias
        }
        exposureDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)

        lastExposureDrag = CGSize(width: 0, height: translationHeight)
    }

    /// Schedules reticle fade-out for non-locked focus states.
    private func scheduleFocusHide() {
        guard !viewModel.lockStatus.isLocked else { return }

        hideFocusWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 1.15)) {
                showFocusIndicator = false
                lastExposureDrag = .zero
            }
        }

        hideFocusWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    /// Cancels pending focus/exposure work items on view disappearance.
    private func cleanupFocusState() {
        hideFocusWorkItem?.cancel()
        hideFocusWorkItem = nil
        exposureDebounceWorkItem?.cancel()
        exposureDebounceWorkItem = nil
        exposureDragBaselineY = 0
        exposureDragBaselineBias = exposureBias
        lastAppliedExposureBias = exposureBias
        lastExposureDrag = .zero
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
