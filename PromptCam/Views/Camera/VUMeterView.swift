import SwiftUI

/// A vertical VU (audio level) meter that displays real-time audio levels
/// with a three-color gradient fill, peak hold indicator, hash marks, dB
/// labels, a latching CLIP indicator, and a no-signal dim state.
struct VUMeterView: View {
    let level: Float
    let peak: Float
    let isExternalMic: Bool
    let isRecording: Bool
    /// Optional source name shown briefly as an inline label when the
    /// route changes. The parent (`CameraView`) clears this after a delay.
    var sourceNameHint: String? = nil

    // MARK: - Constants

    private let peakLineHeight: CGFloat = 2
    private let micIconSize: CGFloat = 14
    /// Normalized peak level (≥ this triggers the CLIP indicator).
    private let clipThreshold: Float = 0.98
    /// Normalized level below this for `noSignalGracePeriod` seconds → dim.
    private let noSignalThreshold: Float = 0.03
    /// Seconds of continuous silence before dimming the meter.
    private let noSignalGracePeriod: TimeInterval = 2.0
    /// Seconds the CLIP latch holds after the last clip event.
    private let clipLatchDuration: TimeInterval = 1.0

    /// dB hash mark positions: (normalized 0–1 position, label string).
    /// Derived from normalizeDecibels: dB → (dB + 60) / 60
    private static let hashMarks: [(position: CGFloat, label: String)] = [
        (1.0,   "0"),     // 0 dB   — clipping
        (0.9,   "-6"),    // -6 dB
        (0.8,   "-12"),   // -12 dB
        (0.667, "-20"),   // -20 dB
        (0.5,   "-30"),   // -30 dB
        (0.333, "-40"),   // -40 dB
    ]

    // MARK: - Latching state

    /// True while the CLIP indicator is held lit after a recent clip event.
    @State private var clipLatched: Bool = false
    /// Task that clears `clipLatched` after `clipLatchDuration`.
    @State private var clipClearTask: Task<Void, Never>?
    /// Timestamp of the last frame where level rose above `noSignalThreshold`.
    @State private var lastSignalTime: Date = Date()

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            // Top padding reserves space for the source icon.
            let topPad: CGFloat = micIconSize + Theme.space4
            let barHeight = height - topPad

            // Bar occupies the left ~55% of width; right side holds dB labels.
            let barWidth = floor(width * 0.55)
            let barCenterX = barWidth / 2
            let labelGap: CGFloat = 4
            let labelX = barWidth + labelGap
            let labelWidth = max(width - labelX, 0)

            let clampedLevel = CGFloat(min(max(level, 0), 1))
            let clampedPeak  = CGFloat(min(max(peak,  0), 1))
            let fillHeight = clampedLevel * barHeight
            let peakY = topPad + barHeight - (clampedPeak * barHeight)

            // Dim the meter when there has been no signal for the grace
            // period AND we are not recording. Recording always shows full
            // brightness so the operator can confirm levels.
            let timeSinceSignal = Date().timeIntervalSince(lastSignalTime)
            let isNoSignal = !isRecording && timeSinceSignal >= noSignalGracePeriod
            let meterOpacity: Double = isNoSignal ? 0.4 : 1.0

            ZStack {
                // Source icon — always visible above the bar
                Image(systemName: isExternalMic ? "mic.fill" : "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: micIconSize, weight: .semibold))
                    .foregroundStyle(isExternalMic ? Theme.purple : Theme.secondaryText)
                    .position(x: barCenterX, y: micIconSize / 2)

                // CLIP latch — small red pill centered above bar when latched
                if clipLatched {
                    Text("CLIP")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.red, in: RoundedRectangle(cornerRadius: 2))
                        .position(x: barCenterX, y: micIconSize / 2)
                        .transition(.opacity)
                }

                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.panelBg.opacity(0.3))
                    .frame(width: barWidth, height: barHeight)
                    .position(x: barCenterX, y: topPad + barHeight / 2)

                // Level fill — gradient rises from bottom
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Theme.green,  location: 0.0),
                                    .init(color: Theme.green,  location: 0.6),
                                    .init(color: Theme.yellow, location: 0.6),
                                    .init(color: Theme.yellow, location: 0.8),
                                    .init(color: Theme.red,    location: 0.8),
                                    .init(color: Theme.red,    location: 1.0),
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: barWidth, height: fillHeight)
                }
                .frame(width: barWidth, height: barHeight)
                .position(x: barCenterX, y: topPad + barHeight / 2)

                // Peak hold indicator
                Rectangle()
                    .fill(Theme.accent.opacity(0.9))
                    .frame(width: barWidth + 4, height: peakLineHeight)
                    .position(x: barCenterX, y: peakY)
                    .animation(.linear(duration: 0.05), value: peak)

                // Hash marks across the bar + dB labels to the right
                ForEach(Array(Self.hashMarks.enumerated()), id: \.offset) { _, mark in
                    let markY = topPad + barHeight - (mark.position * barHeight)

                    Rectangle()
                        .fill(Theme.white.opacity(0.6))
                        .frame(width: barWidth, height: 1)
                        .position(x: barCenterX, y: markY)

                    Text(mark.label)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.white.opacity(0.75))
                        .frame(width: labelWidth + 10, alignment: .leading)
                        .position(x: (labelX + labelWidth / 2) + 5, y: markY)
                }

                // Inline source-name label — shown briefly after route change.
                // Anchored to the right of the bar, vertically centered.
                if let name = sourceNameHint {
                    Text(name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.black.opacity(0.7), in: Capsule())
                        .fixedSize()
                        .position(x: barCenterX + 50, y: topPad + barHeight / 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(width: width, height: height)
            .opacity(meterOpacity)
        }
        .animation(.linear(duration: 0.05), value: level)
        .animation(.easeInOut(duration: 0.3), value: isRecording)
        .animation(.easeInOut(duration: 0.3), value: isExternalMic)
        .animation(.easeInOut(duration: 0.25), value: clipLatched)
        .animation(.easeInOut(duration: 0.25), value: sourceNameHint)
        .onChange(of: peak) { _, newPeak in
            handlePeakChange(newPeak)
        }
        .onChange(of: level) { _, newLevel in
            if newLevel >= noSignalThreshold {
                lastSignalTime = Date()
            }
        }
        .onDisappear {
            clipClearTask?.cancel()
            clipClearTask = nil
        }
    }
    
    

    // MARK: - Helpers

    /// Latches the CLIP indicator on when the peak crosses the threshold
    /// and schedules a clear after `clipLatchDuration`. Successive clips
    /// extend the latch by cancelling and rescheduling.
    private func handlePeakChange(_ newPeak: Float) {
        guard newPeak >= clipThreshold else { return }
        clipLatched = true
        clipClearTask?.cancel()
        clipClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(clipLatchDuration))
            guard !Task.isCancelled else { return }
            clipLatched = false
        }
    }
}

// MARK: - Preview

#Preview("VU Meter") {
    HStack(spacing: 24) {
        VUMeterView(
            level: 0.3,
            peak: 0.5,
            isExternalMic: false,
            isRecording: true
        )
        .frame(width: 50, height: 200)

        VUMeterView(
            level: 0.75,
            peak: 0.99,
            isExternalMic: true,
            isRecording: true,
            sourceNameHint: "USB Mic"
        )
        .frame(width: 50, height: 200)

        VUMeterView(
            level: 0.01,
            peak: 0.02,
            isExternalMic: false,
            isRecording: false
        )
        .frame(width: 50, height: 200)
    }
    .padding()
    .background(Color.black)
}
