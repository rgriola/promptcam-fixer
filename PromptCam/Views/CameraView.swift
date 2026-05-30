// May 29, 2026 - 11:23pm - GitHub Copilot
import SwiftUI

struct CameraView: View {
    @StateObject var viewModel: CameraViewModel
    private let exposureRange: Float = 5.0
    @State private var focusIndicatorPoint: CGPoint?
    @State private var showFocusIndicator = false
    @State private var isFocusLocked = false
    @State private var lastDevicePoint: CGPoint?
    @State private var lastExposureDrag: CGSize = .zero
    @State private var hideFocusWorkItem: DispatchWorkItem?

    @State private var exposureBias: Float = 0

    @State private var exposureDebounceWorkItem: DispatchWorkItem?
    @State private var pendingExposureDelta: Float = 0

    @State private var exposureDragBaselineBias: Float = 0
    @State private var exposureDragBaselineY: CGFloat = 0
    @State private var lastAppliedExposureBias: Float = 0

    var body: some View {

        // this should be moved to a Utility file. 
        GeometryReader { proxy in
            let (barHeight, _) = CameraLayout.barHeights(containerSize: proxy.size)
            let previewAspect: CGFloat = CameraLayout.previewAspect
            let previewHeight = proxy.size.width / previewAspect

            ZStack {
                CameraPreviewView(session: viewModel.session) { devicePoint, viewPoint in
                    viewModel.focus(at: devicePoint)
                    print("Touch Focus")
                    lastDevicePoint = devicePoint
                    withAnimation(.easeOut(duration: 0.15)) {
                        focusIndicatorPoint = CGPoint(x: viewPoint.x, y: viewPoint.y + barHeight)
                        showFocusIndicator = true
                    }

                    scheduleFocusHide()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(previewAspect, contentMode: .fit)

                if showFocusIndicator, let focusIndicatorPoint {
                    FocusIndicatorView(
                        exposureRange: exposureRange,
                        exposureBias: exposureBias,
                        showFocusIndicator: showFocusIndicator,
                        onDragDelta: { translationHeight in
                            // Initialize baseline on gesture start
                            if lastExposureDrag == .zero {
                                exposureDragBaselineBias = exposureBias
                                exposureDragBaselineY = translationHeight
                                lastAppliedExposureBias = exposureBias
                            }

                            // Total delta from where the finger first touched
                            let totalDeltaY = translationHeight - exposureDragBaselineY

                            // Make full +/- range reachable in a shorter drag (~120pt)
                            let scalePerPoint: Float = (exposureRange * 2) / Float(CameraLayout.evFullRangePoints)

                            // Compute new bias from baseline and clamp
                            let newBias = min(max(exposureDragBaselineBias - Float(totalDeltaY) * scalePerPoint, -exposureRange), exposureRange)

                            // Update UI immediately for responsiveness
                            exposureBias = newBias
                            showFocusIndicator = true
                            scheduleFocusHide()

                            // Debounce sending only the net change from last applied bias
                            let pending = newBias - lastAppliedExposureBias
                            exposureDebounceWorkItem?.cancel()
                            let work = DispatchWorkItem {
                                viewModel.adjustExposure(by: pending)
                                lastAppliedExposureBias = newBias
                            }
                            exposureDebounceWorkItem = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)

                            // Track last translation (non-essential now but used as 'drag active' sentinel)
                            lastExposureDrag = CGSize(width: 0, height: translationHeight)
                        },
                        onLongPressToggleLock: {
                            isFocusLocked.toggle()
                            if isFocusLocked, let lastDevicePoint {
                                viewModel.lockFocusExposure(at: lastDevicePoint)
                                showFocusIndicator = true
                            } else {
                                viewModel.unlockFocusExposure()
                                scheduleFocusHide()
                            }
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

                    ZStack {
                        RecordButton(isRecording: viewModel.isRecording) {
                            viewModel.toggleRecording()
                            print("Recording toggled")
                        }
                        .frame(width: 72, height: 72)
                        .offset(y: -28)

                        ScrollToggleButton(isScrolling: viewModel.isScrolling) {
                            viewModel.toggleScrolling()
                            print("Scroll toggled")
                        }
                        .frame(width: 36, height: 36)
                        .offset(x: -72, y: -28)
                    }
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .safeAreaInset(edge: .top, spacing: 0) {
                cameraHeader
                    .frame(height: barHeight)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                cameraFooter
                    .frame(height: barHeight)
            }
        }

        // These should be moved to a one time permission view with check marks on the same screen view. 
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
            hideFocusWorkItem?.cancel()
            hideFocusWorkItem = nil
            exposureDebounceWorkItem?.cancel()
            exposureDebounceWorkItem = nil
            exposureDragBaselineY = 0
            exposureDragBaselineBias = exposureBias
            lastAppliedExposureBias = exposureBias
            lastExposureDrag = .zero
        }
    }

    private var cameraHeader: some View {
        let evValue = min(max(exposureBias, -exposureRange), exposureRange)
        let evText = String(format: "%.1f", evValue)

        return VStack(spacing: Theme.space12) {

            HStack {
                Button {
                    print("EV button tapped")
                } label: {
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

                Circle() // This is camera status indicator - green when active, red when recording
                    .fill(Theme.green)
                    .frame(width: 8, height: 8)

                Spacer()

                Button {
                    print("Grid button tapped")
                } label: {
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
                formatPanel
                Spacer()
            }
        }
        .padding(.horizontal, Theme.space16)
        //.padding(.top, Theme.space16)
        //.padding(.bottom, Theme.space12)
        .frame(maxWidth: .infinity)
       // .background(Theme.black.opacity(0.85))
    }

    private var formatPanel: some View {
        Button {
            print("Format panel tapped")
        } label: {
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
    }


    private var cameraFooter: some View {
        VStack {
            Spacer()
            HStack(spacing: Theme.space12) {
                Spacer()
                circleIconButton(systemName: "photo.on.rectangle") {
                    print("Photo library tapped")
                    }
                .accessibilityLabel("Open photo library")

                Spacer()
                circleIconButton(systemName: "sparkle.text.clipboard"){
                    print("Sparkle Text Tapped")
                    }
                .accessibilityLabel("Insert generated script")

                Spacer()
                circleIconButton(systemName: "sun.max") {
                    print("Sun max Settings Tapped")
                    }
                .accessibilityLabel("Open camera settings")

                Spacer()
                }//.padding(.bottom, Theme.space12)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.black.opacity(0.85))
    }

    private func circleIconButton( // use this for nav bar
        systemName: String,
        size: CGFloat = 44,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.panelBg.opacity(0.9))
                Image(systemName: systemName)
                    .font(Theme.icon20)
                    .foregroundStyle(Theme.white)
            }
            .frame(width: size, height: size)
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


    private func scheduleFocusHide() {
        guard !isFocusLocked else { return }
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

