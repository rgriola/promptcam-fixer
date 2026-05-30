// May 30, 2026 - 11:10am - GitHub Copilot
import SwiftUI

struct CameraView: View {
    @StateObject var viewModel: CameraViewModel
    private let exposureRange: Float = 5.0

    @State private var focusIndicatorPoint: CGPoint?
    @State private var showFocusIndicator = false
    @State private var lastExposureDrag: CGSize = .zero
    @State private var hideFocusWorkItem: DispatchWorkItem?
    @State private var exposureBias: Float = 0
    @State private var exposureDebounceWorkItem: DispatchWorkItem?
    @State private var exposureDragBaselineBias: Float = 0
    @State private var exposureDragBaselineY: CGFloat = 0
    @State private var lastAppliedExposureBias: Float = 0

    var body: some View {
        GeometryReader { proxy in
            let (barHeight, _) = CameraLayout.barHeights(containerSize: proxy.size)
            let previewAspect: CGFloat = CameraLayout.previewAspect

            ZStack {
                CameraPreviewView(
                    session: viewModel.session,
                    onTap: { devicePoint, viewPoint in
                        handlePreviewTap(devicePoint: devicePoint, viewPoint: viewPoint, barHeight: barHeight)
                    },
                    onLongPress: { devicePoint, viewPoint in
                        handlePreviewLongPress(devicePoint: devicePoint, viewPoint: viewPoint, barHeight: barHeight)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(previewAspect, contentMode: .fit)

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

                TeleprompterOverlayView(
                    text: viewModel.config.text,
                    fontSize: viewModel.config.fontSize,
                    speed: viewModel.config.speedPointsPerSecond,
                    isScrolling: viewModel.isScrolling
                )
                .allowsHitTesting(false)
                .padding(.top, barHeight + 50)

                VStack(spacing: 0) {
                    Color.clear
                        .frame(maxHeight: .infinity)
                        .allowsHitTesting(false)

                    RecordingClusterView(
                        isRecording: viewModel.isRecording,
                        isScrolling: viewModel.isScrolling,
                        onRecordTap: {
                            viewModel.toggleRecording()
                            print("Recording toggled")
                        },
                        onScrollTap: {
                            viewModel.toggleScrolling()
                            print("Scroll toggled")
                        }
                    )
                    .offset(y: -28)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .safeAreaInset(edge: .top, spacing: 0) {
                cameraHeader
                    .frame(height: barHeight)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                cameraFooterReservedSpace
                    .frame(height: barHeight)
            }
        }
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

    private var cameraHeader: some View {
        let evValue = min(max(exposureBias, -exposureRange), exposureRange)
        let evText = String(format: "%.1f", evValue)

        return CameraTopControlsView(
            evText: evText,
            lockStatus: viewModel.lockStatus,
            onTapEV: {
                print("EV button tapped")
            },
            onTapGrid: {
                print("Grid button tapped")
            },
            onTapFormat: {
                print("Format panel tapped")
            }
        )
    }

    private var cameraFooterReservedSpace: some View {
        Color.clear
            .frame(maxWidth: .infinity)
    }

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

    private func handlePreviewLongPress(devicePoint: CGPoint, viewPoint: CGPoint, barHeight: CGFloat) {
        print("Preview long press lock attempt")
        updateFocusIndicatorPosition(viewPoint: viewPoint, barHeight: barHeight)
        viewModel.lockFocusExposure(at: devicePoint)
        scheduleFocusHide()
    }

    private func updateFocusIndicatorPosition(viewPoint: CGPoint, barHeight: CGFloat) {
        withAnimation(.easeOut(duration: 0.15)) {
            focusIndicatorPoint = CGPoint(x: viewPoint.x, y: viewPoint.y + barHeight)
            showFocusIndicator = true
        }
    }

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
}

private struct CameraTopControlsView: View {
    let evText: String
    let lockStatus: CameraLockStatus
    let onTapEV: () -> Void
    let onTapGrid: () -> Void
    let onTapFormat: () -> Void

    var body: some View {
        VStack(spacing: Theme.space12) {
            HStack {
                Button(action: onTapEV) {
                    Text("EV \(evText)")
                        .font(Theme.mono10Medium)
                        .foregroundStyle(Theme.white)
                        .padding(.horizontal, Theme.space12)
                        .padding(.vertical, Theme.space8)
                        .background(Theme.panelBg.opacity(0.9), in: Capsule())
                        .accessibilityLabel("Exposure value")
                        .accessibilityHint("Shows current exposure bias")
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
        .padding(.horizontal, Theme.space16)
        .frame(maxWidth: .infinity)
    }
}

private struct CameraLockStatusBadgeView: View {
    let status: CameraLockStatus

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

private struct RecordingClusterView: View {
    let isRecording: Bool
    let isScrolling: Bool
    let onRecordTap: () -> Void
    let onScrollTap: () -> Void

    var body: some View {
        ZStack {
            RecordButton(isRecording: isRecording, action: onRecordTap)
                .frame(width: 72, height: 72)

            ScrollToggleButton(isScrolling: isScrolling, action: onScrollTap)
                .frame(width: 36, height: 36)
                .offset(x: -72)
        }
    }
}

private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

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
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint("Toggles video recording")
    }
}

private struct ScrollToggleButton: View {
    let isScrolling: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Theme.white, lineWidth: 4)
                Circle().fill(isScrolling ? Theme.blueScrollPreview : Theme.blue)
                Image(systemName: isScrolling ? "play.fill" : "pause.fill")
                    .font(Theme.icon12)
                    .foregroundStyle(Theme.white)
            }
        }
        .accessibilityLabel(isScrolling ? "Pause teleprompter" : "Play teleprompter")
        .accessibilityHint("Toggles teleprompter scrolling")
    }
}

#Preview("RecordButton - Idle") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        RecordButton(isRecording: false) {}
            .frame(width: 72, height: 72)
    }
}

#Preview("RecordButton - Recording") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        RecordButton(isRecording: true) {}
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
