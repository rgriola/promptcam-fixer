import SwiftUI

// MARK: - VUMeterView

/// A vertical VU (audio level) meter that displays real-time audio levels
/// with a three-color gradient fill, peak hold indicator, hash marks, dB
/// labels, a latching CLIP indicator, and a no-signal dim state.
///
/// **Stereo mode**: when `level2` / `peak2` are non-nil (e.g. a dual-channel
/// wireless receiver is connected), the bar area splits into two half-width
/// bars labeled "1" and "2", each metered independently. The outer frame
/// and position in `CameraView` are unchanged.
struct VUMeterView: View {
    let level: Float
    let peak: Float
    let isExternalMic: Bool
    let isRecording: Bool
    /// Optional second channel — non-nil when a stereo input is active.
    var level2: Float? = nil
    var peak2: Float?  = nil
    /// Optional source name shown briefly as an inline label when the
    /// route changes. The parent (`CameraView`) clears this after a delay.
    var sourceNameHint: String? = nil

    // MARK: - Constants

    private let micIconSize: CGFloat = 14
    private let channelGap: CGFloat  = 3   // gap between Ch1 and Ch2 bars in stereo mode

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

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let width  = geo.size.width
            let height = geo.size.height

            // Top padding reserves space for the source icon / channel labels.
            let topPad: CGFloat = micIconSize + Theme.space4

            // The bar column occupies ~55% of width; right side holds dB labels.
            let barColumnWidth = floor(width * 0.55)
            let labelGap: CGFloat = 4
            let labelX = barColumnWidth + labelGap
            let labelWidth = max(width - labelX, 0)
            let barHeight = height - topPad

            let isStereo = level2 != nil

            // In stereo mode the two bars share the barColumnWidth with a gap.
            let singleBarWidth: CGFloat = isStereo
                ? floor((barColumnWidth - channelGap) / 2)
                : barColumnWidth

            // X centers for Ch1 and (optional) Ch2
            let ch1CenterX: CGFloat = singleBarWidth / 2
            let ch2CenterX: CGFloat = isStereo ? singleBarWidth + channelGap + singleBarWidth / 2 : 0

            ZStack {
                // MARK: Source icon / channel labels
                if isStereo {
                    // Channel labels "1" and "2" replace the mic icon in stereo mode.
                    Text("1")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.white)
                        .position(x: ch1CenterX, y: micIconSize / 2)
                    Text("2")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.white)
                        .position(x: ch2CenterX, y: micIconSize / 2)
                } else {
                    Image(systemName: isExternalMic
                          ? "mic.fill"
                          : "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: micIconSize, weight: .semibold))
                        .foregroundStyle(isExternalMic ? Theme.white : Theme.white)
                        .position(x: ch1CenterX, y: micIconSize / 2)
                }

                // MARK: Ch1 bar
                VUBarView(
                    level: level,
                    peak: peak,
                    barWidth: singleBarWidth,
                    barHeight: barHeight,
                    topPad: topPad,
                    centerX: ch1CenterX,
                    isRecording: isRecording
                )

                // MARK: Ch2 bar (stereo only)
                if let l2 = level2, let p2 = peak2 {
                    VUBarView(
                        level: l2,
                        peak: p2,
                        barWidth: singleBarWidth,
                        barHeight: barHeight,
                        topPad: topPad,
                        centerX: ch2CenterX,
                        isRecording: isRecording
                    )
                }

                // MARK: dB hash marks + labels (span the full bar column)
                ForEach(Array(Self.hashMarks.enumerated()), id: \.offset) { _, mark in
                    let markY = topPad + barHeight - (mark.position * barHeight)

                    Rectangle()
                        .fill(Theme.white.opacity(0.8))
                        .frame(width: barColumnWidth, height: 1)
                        .position(x: barColumnWidth / 2, y: markY)

                    Text(mark.label)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.white.opacity(0.8))
                        .frame(width: labelWidth + 10, alignment: .leading)
                        .position(x: (labelX + labelWidth / 2) + 5, y: markY)
                }

                // MARK: Inline source-name hint
                if let name = sourceNameHint {
                    Text(name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.black.opacity(0.7), in: Capsule())
                        .fixedSize()
                        .position(x: ch1CenterX + 50, y: topPad + barHeight / 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(width: width, height: height)
        }
        .animation(.linear(duration: 0.05),    value: level)
        .animation(.linear(duration: 0.05),    value: level2)
        .animation(.easeInOut(duration: 0.3),  value: isRecording)
        .animation(.easeInOut(duration: 0.3),  value: isExternalMic)
        .animation(.easeInOut(duration: 0.25), value: sourceNameHint)
        .animation(.easeInOut(duration: 0.4),  value: level2 != nil) // bar split/merge
    }
}

// MARK: - VUBarView

/// A single vertical bar of the VU meter — gradient fill, peak hold line,
/// CLIP latch indicator, and no-signal dim. Used by `VUMeterView` for both
/// the mono bar and each channel bar in stereo mode.
private struct VUBarView: View {
    let level: Float
    let peak: Float
    let barWidth: CGFloat
    let barHeight: CGFloat
    let topPad: CGFloat
    let centerX: CGFloat
    let isRecording: Bool

    private let peakLineHeight: CGFloat = 2
    private let clipThreshold: Float    = 0.98
    private let noSignalThreshold: Float = 0.03
    private let noSignalGracePeriod: TimeInterval = 2.0
    private let clipLatchDuration: TimeInterval   = 1.0

    @State private var clipLatched: Bool = false
    @State private var clipClearTask: Task<Void, Never>?
    @State private var lastSignalTime: Date = Date()
    /// Driven by .task(id: lastSignalTime) so SwiftUI re-renders correctly
    /// when the grace period elapses — Date() in body is not reactive.
    @State private var isNoSignal: Bool = false

    private static let levelGradient = LinearGradient(
        stops: [
            .init(color: VUColor.floor,  location: 0.0),
            .init(color: VUColor.stepOne,  location: 0.6),
            .init(color: VUColor.stepTwo, location: 0.7),
            .init(color: VUColor.stepThree, location: 0.8),
            .init(color: VUColor.stepFour,    location: 0.9),
            .init(color: VUColor.peak,   location: 1.0),
        ],
        startPoint: .bottom,
        endPoint: .top
    )

    var body: some View {
        let clampedLevel = CGFloat(min(max(level, 0), 1))
        let clampedPeak  = CGFloat(min(max(peak,  0), 1))
        let fillHeight   = clampedLevel * barHeight
        let peakY        = topPad + barHeight - (clampedPeak * barHeight)

        let meterOpacity: Double = isNoSignal ? 0.4 : 1.0

        ZStack {
            // Background track
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.panelBg.opacity(0.4))
                .frame(width: barWidth, height: barHeight)
                .position(x: centerX, y: topPad + barHeight / 2)

            // Level fill — gradient rises from bottom
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Self.levelGradient)
                    .frame(width: barWidth, height: fillHeight)
            }
            .frame(width: barWidth, height: barHeight)
            .position(x: centerX, y: topPad + barHeight / 2)

            // Peak hold line
            Rectangle()
                .fill(Theme.accent.opacity(0.9))
                .frame(width: barWidth + 2, height: peakLineHeight)
                .position(x: centerX, y: peakY)
                .animation(.linear(duration: 0.05), value: peak)

            // CLIP latch
            if clipLatched {
                Text("CLIP")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Theme.red, in: RoundedRectangle(cornerRadius: 2))
                    .position(x: centerX, y: topPad - 6)
                    .transition(.opacity)
            }
        }
        .opacity(meterOpacity)
        .onChange(of: peak) { _, newPeak in
            guard newPeak >= clipThreshold else { return }
            clipLatched = true
            clipClearTask?.cancel()
            clipClearTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(clipLatchDuration))
                guard !Task.isCancelled else { return }
                clipLatched = false
            }
        }
        .onChange(of: level) { _, newLevel in
            if newLevel >= noSignalThreshold {
                lastSignalTime = Date()
                isNoSignal = false
            }
        }
        .onChange(of: isRecording) { _, recording in
            // Clear no-signal state immediately when recording starts.
            if recording { isNoSignal = false }
        }
        // Restarts whenever lastSignalTime updates (i.e. on any real signal).
        // After the grace period with no new signal, marks the meter as no-signal.
        .task(id: lastSignalTime) {
            try? await Task.sleep(for: .seconds(noSignalGracePeriod))
            if !isRecording {
                isNoSignal = true
            }
        }
        .onDisappear {
            clipClearTask?.cancel()
            clipClearTask = nil
        }
        .animation(.easeInOut(duration: 0.25), value: clipLatched)
        .animation(.easeInOut(duration: 0.3),  value: isRecording)
        .animation(.easeInOut(duration: 0.5),  value: isNoSignal)
    }
}

// MARK: - Preview

#Preview("VU Meter — Mono") {
    HStack(spacing: 24) {
        VUMeterView(level: 0.3,  peak: 0.5,  isExternalMic: false, isRecording: true)
            .frame(width: 50, height: 200)
        VUMeterView(level: 0.75, peak: 0.99, isExternalMic: true,  isRecording: true, sourceNameHint: "Wireless Rx")
            .frame(width: 50, height: 200)
        VUMeterView(level: 0.01, peak: 0.02, isExternalMic: false, isRecording: false)
            .frame(width: 50, height: 200)
    }
    .padding()
    .background(Theme.black)
}

#Preview("VU Meter — Stereo") {
    HStack(spacing: 24) {
        // Both channels active
        VUMeterView(
            level: 0.6,  peak: 0.8,
            isExternalMic: true, isRecording: true,
            level2: 0.4, peak2: 0.65
        )
        .frame(width: 50, height: 200)

        // One channel silent (dual-mono: one mic active)
        VUMeterView(
            level: 0.55, peak: 0.7,
            isExternalMic: true, isRecording: true,
            level2: 0.0, peak2: 0.0
        )
        .frame(width: 50, height: 200)

        // Near-clip on Ch1
        VUMeterView(
            level: 0.97, peak: 0.99,
            isExternalMic: true, isRecording: true,
            level2: 0.3,  peak2: 0.45
        )
        .frame(width: 50, height: 200)
    }
    .padding()
    .background(Theme.black)
}
