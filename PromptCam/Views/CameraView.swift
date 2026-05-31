// May 30, 2026 - 10:28pm - GitHub Copilot
import PhotosUI
import SwiftUI

// MARK: - Camera Screen Layout Tokens
private enum CameraChromeLayout {
    /// Vertical adjustment for the top control row cluster.
    static let topRowDrop: CGFloat = 0
    /// Horizontal inset for header controls.
    static let headerHorizontalPadding: CGFloat = 16
    /// Bottom inset under the header cluster.
    static let headerBottomPadding: CGFloat = 0
    /// Vertical offset for the full header container.
    static let headerVerticalOffset: CGFloat = 0
    /// Bottom spacing between record cluster and footer bar.
    static let recordingBottomPadding: CGFloat = 18
    /// Extra footer bar height if additional chrome is introduced.
    static let footerBarExtraHeight: CGFloat = 0
    /// Bottom inset inside footer controls.
    static let footerBottomPadding: CGFloat = 0
    /// Moves footer controls lower to align with approved design.
    static let footerVerticalOffset: CGFloat = 38 // adjusts footer elements downward.
    /// Shared circular icon button size for footer controls.
    static let footerIconSize: CGFloat = 44
    /// Sets teleprompter viewport height (length knob).
    static let teleprompterViewportHeight: CGFloat = 500
    /// Sets distance from preview bottom edge to viewport bottom (position knob).
    static let teleprompterBottomInset: CGFloat = 140
    /// Width of the right-side drag lane for adjusting script start position.
    static let teleprompterDragLaneWidth: CGFloat = 34
    /// Horizontal inset from the preview right edge for drag lane placement.
    static let teleprompterDragLaneEdgeInset: CGFloat = 18
}

/// Primary camera surface that composes preview, teleprompter, and control chrome.
struct CameraView: View {
    /// View model that owns camera state, routes, and actions.
    @StateObject var viewModel: CameraViewModel
    /// Maximum absolute EV value used by focus/exposure drag calculations.
    private let exposureRange: Float = 5.0

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
    /// Temporary media selection binding for PhotosPicker.
    @State private var selectedMediaItem: PhotosPickerItem?
    /// Last measured teleprompter text height used to map drag travel range.
    @State private var teleprompterTextHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            // Shared geometry values for safe-area-aware camera composition.
            let (barHeight, previewHeight) = CameraLayout.barHeights(containerSize: proxy.size)
            let previewCenter = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let previewTopY = previewCenter.y - (previewHeight / 2)
            let previewBottomY = previewCenter.y + (previewHeight / 2)
            let teleprompterViewportHeight = min(max(CameraChromeLayout.teleprompterViewportHeight, 0), previewHeight)
            let minTeleprompterCenterY = previewTopY + (teleprompterViewportHeight / 2)
            let maxTeleprompterCenterY = previewBottomY - (teleprompterViewportHeight / 2)
            let requestedTeleprompterCenterY = previewBottomY - CameraChromeLayout.teleprompterBottomInset - (teleprompterViewportHeight / 2)
            let teleprompterCenterY = min(max(requestedTeleprompterCenterY, minTeleprompterCenterY), maxTeleprompterCenterY)
            let teleprompterDragLaneX = previewCenter.x + (proxy.size.width / 2) - CameraChromeLayout.teleprompterDragLaneEdgeInset
            let safeTopInset = proxy.safeAreaInsets.top
            let safeBottomInset = proxy.safeAreaInsets.bottom

            ZStack {
                // Live camera preview layer with tap and long-press gesture hooks.
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

                // Focus reticle + EV drag layer shown after tap/long-press interaction.
                if showFocusIndicator, let focusIndicatorPoint {
                    FocusIndicatorView(
                        exposureRange: exposureRange,
                        exposureBias: exposureBias,
                        showFocusIndicator: showFocusIndicator,
                        onDragDelta: { translationHeight in
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
                    )
                    .position(focusIndicatorPoint)
                }

                // Header, record cluster, and footer chrome above preview.
                VStack(spacing: 0) {
                    cameraHeader(safeTopInset: safeTopInset)
                        .frame(height: barHeight + safeTopInset, alignment: .top)
                        .offset(y: CameraChromeLayout.headerVerticalOffset)

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
                    .padding(.bottom, CameraChromeLayout.recordingBottomPadding)

                    cameraFooter(safeBottomInset: safeBottomInset)
                        .frame(height: barHeight + CameraChromeLayout.footerBarExtraHeight + safeBottomInset, alignment: .bottom)
                        .offset(y: CameraChromeLayout.footerVerticalOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom-anchored teleprompter viewport with independent size and position knobs.
                TeleprompterOverlayView(
                    text: viewModel.config.text,
                    fontSize: viewModel.config.fontSize,
                    speed: viewModel.config.speedPointsPerSecond,
                    isScrolling: viewModel.isScrolling,
                    startOffsetProgress: viewModel.config.startOffsetProgress,
                    onTextHeightChanged: { measuredHeight in
                        teleprompterTextHeight = measuredHeight
                    }
                )
                .frame(width: proxy.size.width, height: teleprompterViewportHeight)
                .position(x: previewCenter.x, y: teleprompterCenterY)
                .allowsHitTesting(false)

                // Right-side lane for manual script start-position adjustment.
                TeleprompterStartOffsetLane(
                    isEnabled: !viewModel.isScrolling,
                    currentProgress: viewModel.config.startOffsetProgress,
                    onProgressChanged: { progress in
                        handleStartOffsetProgressChanged(progress)
                    },
                    onDragEnded: {
                        // no-op
                    }
                )
                .frame(width: CameraChromeLayout.teleprompterDragLaneWidth, height: teleprompterViewportHeight)
                .position(x: teleprompterDragLaneX, y: teleprompterCenterY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Permission and runtime error feedback.
        .alert("Permissions Required", isPresented: $viewModel.showPermissionsAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enable camera, microphone, and photo library permissions in Settings.")
        }
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
        // Media import route from footer photo action.
        .photosPicker(
            isPresented: $viewModel.isPhotoPickerPresented,
            selection: $selectedMediaItem,
            matching: .videos,
            preferredItemEncoding: .automatic
        )
        // Routed sheets for format, compose, and settings.
        .sheet(item: $viewModel.activeSheet) { route in
            sheetContent(for: route)
        }
        // Screen lifecycle hooks for camera startup and cleanup.
        .onAppear { viewModel.onAppear() }
        .onDisappear {
            viewModel.onDisappear()
            viewModel.unlockFocusExposure()
            hideFocusWorkItem?.cancel()
            hideFocusWorkItem = nil
            exposureDebounceWorkItem?.cancel()
            exposureDebounceWorkItem = nil
            exposureDragBaselineY = 0
            exposureDragBaselineBias = exposureBias
            lastAppliedExposureBias = exposureBias
            lastExposureDrag = .zero
        }
        // Picker result handler (placeholder until ingest pipeline is wired).
        .onChange(of: selectedMediaItem) { newItem in
            guard newItem != nil else { return }
            print("Media selected from library picker")
            selectedMediaItem = nil
        }
        // Modal lifecycle relays used by the view model presentation queue.
        .onChange(of: viewModel.activeSheet) { newValue in
            viewModel.handleSheetStateChanged(newValue)
        }
        .onChange(of: viewModel.isPhotoPickerPresented) { newValue in
            viewModel.handlePhotoPickerStateChanged(newValue)
        }
        .onChange(of: viewModel.lockStatus) { newStatus in
            switch newStatus {
            case .aeAfLocked:
                print("AE/AF lock engaged")
                showFocusIndicator = true
                hideFocusWorkItem?.cancel()
                hideFocusWorkItem = nil
            case .aeLocked:
                print("AE lock fallback engaged")
                showFocusIndicator = true
                hideFocusWorkItem?.cancel()
                hideFocusWorkItem = nil
            case .afLocked:
                print("AF lock engaged")
                showFocusIndicator = true
                hideFocusWorkItem?.cancel()
                hideFocusWorkItem = nil
            case .unsupported:
                print("Lock unavailable on this camera")
                scheduleFocusHide()
            case .auto:
                print("Lock status set to AUTO")
                scheduleFocusHide()
            }
        }
    }

    /// Builds the top camera controls row and format quick panel.
    /// - Parameter safeTopInset: Safe-area inset used to anchor controls below the notch.
    /// - Returns: Configured top controls view.
    private func cameraHeader(safeTopInset: CGFloat) -> some View {
        let evValue = min(max(exposureBias, -exposureRange), exposureRange)
        let evText = String(format: "%.1f", evValue)

        return CameraTopControlsView(
            evText: evText,
            lockStatus: viewModel.lockStatus,
            safeTopInset: safeTopInset,
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

    /// Handles single tap to focus and return to auto lock mode when needed.
    /// - Parameters:
    ///   - devicePoint: Normalized camera-space point used by AVFoundation focus APIs.
    ///   - viewPoint: View-space touch location used to place the reticle.
    ///   - barHeight: Top letterbox height used to translate reticle coordinates.
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
    /// - Parameters:
    ///   - devicePoint: Normalized camera-space point used for lock request.
    ///   - viewPoint: View-space touch location used to position the reticle.
    ///   - barHeight: Top letterbox height used to align reticle coordinates.
    private func handlePreviewLongPress(devicePoint: CGPoint, viewPoint: CGPoint, barHeight: CGFloat) {
        print("Preview long press lock attempt")
        updateFocusIndicatorPosition(viewPoint: viewPoint, barHeight: barHeight)
        viewModel.lockFocusExposure(at: devicePoint)
        scheduleFocusHide()
    }

    /// Positions and shows the focus indicator using preview touch coordinates.
    /// - Parameters:
    ///   - viewPoint: Touch location from preview view coordinates.
    ///   - barHeight: Letterbox offset used to translate to parent coordinates.
    private func updateFocusIndicatorPosition(viewPoint: CGPoint, barHeight: CGFloat) {
        withAnimation(.easeOut(duration: 0.15)) {
            focusIndicatorPoint = CGPoint(x: viewPoint.x, y: viewPoint.y + barHeight)
            showFocusIndicator = true
        }
    }

    /// Applies a normalized progress value from the drag lane while paused.
    /// - Parameter progress: Normalized start progress where 0 places the first line off-screen below and 1 places it off-screen above; 0.5 centers it.
    private func handleStartOffsetProgressChanged(_ progress: Double) {
        guard !viewModel.isScrolling else { return }

        viewModel.updateScriptStartProgress(progress)
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

    @ViewBuilder
    /// Routes the currently active sheet to its destination content.
    /// - Parameter route: Selected modal route from the view model.
    /// - Returns: Sheet content view for the selected route.
    private func sheetContent(for route: CameraSheetRoute) -> some View {
        switch route {
        case .formatPanel:
            CameraFormatPanelSheet {
                viewModel.dismissActiveSheet()
            }
        case .composeScript:
            ComposeScriptSheet(
                initialText: viewModel.config.text,
                onSave: { text in
                    viewModel.updateScriptText(text)
                    // Reset to knob-top so first line of the freshly-pasted script sits at viewport bottom,
                    // ready to scroll up. Recalculated against the new script's measured height by the overlay.
                    viewModel.updateScriptStartProgress(1.0)
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

// MARK: - Top Header Controls
private struct CameraTopControlsView: View {
    /// Formatted EV display value shown in the left pill.
    let evText: String
    /// Current focus/exposure lock state shown in the center badge.
    let lockStatus: CameraLockStatus
    /// Device safe-area top inset used for notch-aware placement.
    let safeTopInset: CGFloat
    /// Action for tapping the EV pill.
    let onTapEV: () -> Void
    /// Action for tapping the grid toggle button.
    let onTapGrid: () -> Void
    /// Action for tapping the format quick panel.
    let onTapFormat: () -> Void

    /// Header layout containing EV, lock status, grid, and format controls.
    var body: some View {
        // Header rows are intentionally compact to preserve preview space.
        VStack(spacing: 0) {
            HStack {
                Button(action: onTapEV) {
                    Text("EV \(evText)") // These control the look of the panels
                        .font(Theme.mono10Medium)
                        .foregroundStyle(Theme.white)
                        .padding(.horizontal, Theme.space12)
                        .padding(.vertical, Theme.space8)
                        .background(Theme.panelBg.opacity(0.9), in: Capsule())
                        .accessibilityLabel("Exposure value")
                        .accessibilityHint("Shows current exposure")
                }

                Spacer()

                CameraLockStatusBadgeView(status: lockStatus)

                Spacer()

                Button(action: onTapGrid) {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(Theme.icon20)
                        .foregroundStyle(Theme.white)
                        .padding(10)
                        .background(Theme.panelBg.opacity(0.9), in: Circle())
                        .accessibilityLabel("Toggle grid")
                        .accessibilityHint("Shows or hides the composition grid")
                }
            }
            .padding(.top, max(safeTopInset - 200, 0) + CameraChromeLayout.topRowDrop)

            HStack {
                Button(action: onTapFormat) {
                    HStack(spacing: Theme.space8) {
                        Text("HD")
                            .font(Theme.font16Semibold)
                        Text("RES")
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.secondaryText)
                        Divider()
                            .frame(height: 14)
                            .overlay(Theme.separator)
                        Text("30")
                            .font(Theme.font16Semibold)
                        Text("FPS")
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, Theme.space12)
                    .padding(.vertical, Theme.space8)
                    .background(Theme.panelBg.opacity(0.9), in: Capsule())
                }
                .accessibilityLabel("Format panel")
                .accessibilityHint("Opens camera record format settings")

                Spacer()
            }
        }
        .padding(.horizontal, CameraChromeLayout.headerHorizontalPadding)
        .padding(.bottom, CameraChromeLayout.headerBottomPadding)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Lock Status Badge
private struct CameraLockStatusBadgeView: View {
    /// Lock status used to derive badge text and color.
    let status: CameraLockStatus

    /// Semantic color for current lock state.
    private var statusColor: Color {
        switch status {
        case .auto:
            return Theme.green
        case .unsupported:
            return Theme.yellow
        case .aeAfLocked, .aeLocked, .afLocked:
            return Theme.yellow
        }
    }

    /// Badge pill that surfaces current autofocus/exposure state.
    var body: some View {
        Text(status.text)
            .font(Theme.mono10Medium)
            .foregroundStyle(statusColor)
            .padding(.horizontal, Theme.space12)
            .padding(.vertical, Theme.space8)
            .background(Theme.panelBg.opacity(0.9), in: Capsule())
            .accessibilityLabel("Focus and exposure lock status")
            .accessibilityValue(status.text)
    }
}

// MARK: - Center Record Cluster
private struct RecordingClusterView: View {
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
                .frame(width: 36, height: 36)
                .offset(x: -72)
        }
    }
}

// MARK: - Bottom Footer Controls
private struct CameraFooterControlsView: View {
    /// Device safe-area bottom inset for home-indicator spacing.
    let safeBottomInset: CGFloat
    /// Action to open PhotosPicker.
    let onTapPhotoLibrary: () -> Void
    /// Action to open compose sheet.
    let onTapScriptAssist: () -> Void
    /// Action to open settings sheet.
    let onTapSettings: () -> Void

    /// Footer control row for media import and utility actions.
    var body: some View {
        HStack(spacing: Theme.space12) {
            Spacer()

            footerIconButton(systemName: "photo.on.rectangle", action: onTapPhotoLibrary)
                .accessibilityLabel("Open photo library")

            Spacer()

            footerIconButton(systemName: "sparkle.text.clipboard", action: onTapScriptAssist)
                .accessibilityLabel("Insert generated script")

            Spacer()

            footerIconButton(systemName: "sun.max", action: onTapSettings)
                .accessibilityLabel("Open camera settings")

            Spacer()
        }
        .padding(.bottom, max(safeBottomInset - 18, 0) + CameraChromeLayout.footerBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Shared circular icon button used by footer controls.
    /// - Parameters:
    ///   - systemName: SF Symbol identifier for the icon.
    ///   - action: Callback fired when the footer icon is tapped.
    /// - Returns: Styled footer icon button.
    private func footerIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.panelBg.opacity(0.9))
                Image(systemName: systemName)
                    .font(Theme.icon20)
                    .foregroundStyle(Theme.white)
            }
            .frame(width: CameraChromeLayout.footerIconSize, height: CameraChromeLayout.footerIconSize)
        }
    }
}

// MARK: - Start Offset Drag Lane
private struct TeleprompterStartOffsetLane: View {
    /// Enables drag interaction only while teleprompter is paused.
    let isEnabled: Bool
    /// Current normalized start progress (0 bottom, 1 top).
    let currentProgress: Double
    /// Called continuously as normalized progress changes.
    let onProgressChanged: (Double) -> Void
    /// Called when drag interaction ends.
    let onDragEnded: () -> Void

    /// Vertical lane used to manually tune script starting offset.
    var body: some View {
        GeometryReader { geometry in
            let laneHeight = max(geometry.size.height, 1)
            let clampedProgress = min(max(currentProgress, 0), 1)
            let indicatorY = (1 - clampedProgress) * laneHeight

            ZStack {
                Capsule()
                    .fill(Theme.panelBg.opacity(isEnabled ? 0.42 : 0.2))
                    .frame(width: 6)

                Circle()
                    .fill(Theme.white.opacity(isEnabled ? 0.9 : 0.45))
                    .frame(width: 16, height: 16)
                    .position(x: geometry.size.width / 2, y: indicatorY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.65)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }

                        let clampedY = min(max(value.location.y, 0), laneHeight)
                        let progress = 1 - (clampedY / laneHeight)
                        onProgressChanged(Double(progress))
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
            .accessibilityLabel("Adjust script start position")
            .accessibilityHint(
                isEnabled
                    ? "Drag up or down to change where the script starts before scrolling."
                    : "Pause scrolling to adjust script start position."
            )
        }
    }
}

// MARK: - Record Button
private struct RecordButton: View {
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
                Circle().strokeBorder(Theme.white, lineWidth: 4)
                Circle().fill(isRecording ? Theme.redRecordPreview : Theme.red)
                if isRecording {
                    Image(systemName: "square.fill")
                        .font(Theme.icon16)
                        .foregroundStyle(Theme.white)
                }
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint("Toggles video recording")
    }
}

// MARK: - Scroll Toggle Button
private struct ScrollToggleButton: View {
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

// MARK: - Format Sheet
private struct CameraFormatPanelSheet: View {
    /// Local placeholder selected resolution value.
    @State private var selectedResolution = "HD"
    /// Local placeholder selected frames-per-second value.
    @State private var selectedFPS = "30"
    /// Callback to dismiss the format sheet.
    let onClose: () -> Void

    /// Format selection sheet placeholder for upcoming camera config wiring.
    var body: some View {
        NavigationStack {
            List {
                Section("Recording Format") {
                    Picker("Resolution", selection: $selectedResolution) {
                        Text("HD").tag("HD")
                        Text("4K").tag("4K")
                    }
                    .pickerStyle(.segmented)

                    Picker("Frame Rate", selection: $selectedFPS) {
                        Text("24 FPS").tag("24")
                        Text("30 FPS").tag("30")
                        Text("60 FPS").tag("60")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Status") {
                    Text("Format panel routing is wired. Device recording configuration wiring is next.")
                        .font(Theme.font12Regular)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle("Format")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                }
            }
        }
    }
}

// MARK: - Compose Sheet
private struct ComposeScriptSheet: View {
    /// Local draft text edited before save is committed.
    @State private var draftText: String
    /// Focus binding used to open the keyboard on sheet presentation.
    @FocusState private var isEditorFocused: Bool
    /// Callback fired with latest text when user saves.
    let onSave: (String) -> Void
    /// Callback fired when user cancels editing.
    let onCancel: () -> Void

    /// Creates compose sheet state from current teleprompter text.
    /// - Parameters:
    ///   - initialText: Source text shown when compose opens.
    ///   - onSave: Callback invoked with user-edited script.
    ///   - onCancel: Callback invoked when user dismisses without saving.
    init(initialText: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _draftText = State(initialValue: initialText)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    /// Script editor UI with immediate keyboard focus.
    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.space12) {
                TextEditor(text: $draftText)
                    .font(Theme.font16Regular)
                    .focused($isEditorFocused)
                    .padding(Theme.space8)
                    .background(Theme.panelBg.opacity(0.2), in: RoundedRectangle(cornerRadius: Theme.radiusMd))

                Text("Edits are applied to the teleprompter text when you tap Save.")
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.space16)
            .navigationTitle("Compose")
            .onAppear {
                DispatchQueue.main.async {
                    isEditorFocused = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(draftText)
                    }
                }
            }
        }
    }
}

// MARK: - Settings Sheet
private struct CameraSettingsSheet: View {
    /// Callback to dismiss settings sheet.
    let onClose: () -> Void

    /// Settings placeholder showing app and permission status.
    var body: some View {
        NavigationStack {
            List {
                Section("PromptCam") {
                    SettingStatusRow(title: "Version", value: appVersion)
                }

                Section("Permissions") {
                    SettingStatusRow(title: "Camera + Microphone", value: "Requested on launch")
                    SettingStatusRow(title: "Photo Library Add", value: "Requested when saving recording")
                }

                Section("Status") {
                    Text("Settings route wiring is active. Detailed controls can be added in Phase 6.")
                        .font(Theme.font12Regular)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                }
            }
        }
    }

    /// Human-readable app version/build string shown in settings.
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Reusable Settings Row
private struct SettingStatusRow: View {
    /// Left-side label for the setting item.
    let title: String
    /// Right-side value text for the setting item.
    let value: String

    /// Two-column status row used in settings sections.
    var body: some View {
        HStack {
            Text(title)
                .font(Theme.font16Medium)

            Spacer()

            Text(value)
                .font(Theme.font12Medium)
                .foregroundStyle(Theme.secondaryText)
        }
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
            .frame(width: 36, height: 36)
    }
}

#Preview("ScrollToggleButton - Scrolling") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        ScrollToggleButton(isScrolling: true) {}
            .frame(width: 36, height: 36)
    }
}
