import SwiftUI

/// A vertical VU (audio level) meter that displays real-time audio levels
/// with a three-color gradient fill, peak hold indicator, hash marks, and
/// dB labels.
struct VUMeterView: View {
    let level: Float
    let peak: Float
    let isExternalMic: Bool
    let isRecording: Bool

    // MARK: - Constants

    private let peakLineHeight: CGFloat = 2
    private let micIconSize: CGFloat = 14

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

    // MARK: - Gradient colors

    private let vuGreen = Color(hex: "#c734b6")
    private let vuYellow = Color(hex: "#0a99ff")
    private let vuRed = Color(hex: "#FF3B30")

    // MARK: - Body

    var body: some View {
        VStack(spacing: Theme.space4) {
            // External mic indicator
            if isExternalMic {
                Image(systemName: "mic.fill")
                    .font(.system(size: micIconSize, weight: .semibold))
                    .foregroundStyle(Theme.purple)
                    .transition(.opacity)
            }

            // Meter bar with hash marks
            meterBar
        }
        .opacity(isRecording ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.25), value: isRecording)
        .animation(.easeInOut(duration: 0.3), value: isExternalMic)
    }

    // MARK: - Meter bar

    private var meterBar: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = geo.size.width
            let barWidth = width * 0.45        // Bar takes ~45% of width
            let barX = width - barWidth         // Bar on the right side
            let clampedLevel = CGFloat(min(max(level, 0), 1))
            let clampedPeak = CGFloat(min(max(peak, 0), 1))
            let fillHeight = clampedLevel * height
            let peakY = height - (clampedPeak * height)

            ZStack(alignment: .bottom) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.panelBg.opacity(0.3))
                    .frame(width: barWidth)
                    .position(x: barX + barWidth / 2, y: height / 2)

                // Filled portion (gradient from bottom)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: vuGreen, location: 0.0),
                                    .init(color: vuGreen, location: 0.6),
                                    .init(color: vuYellow, location: 0.6),
                                    .init(color: vuYellow, location: 0.8),
                                    .init(color: vuRed, location: 0.8),
                                    .init(color: vuRed, location: 1.0),
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: barWidth, height: fillHeight)
                }
                .frame(width: barWidth, height: height)
                .position(x: barX + barWidth / 2, y: height / 2)

                // Peak hold indicator
                Rectangle()
                    .fill(Theme.accent.opacity(0.9))
                    .frame(width: barWidth + 4, height: peakLineHeight)
                    .position(x: barX + barWidth / 2, y: peakY)
                    .animation(.linear(duration: 0.05), value: peak)

                // Hash marks with dB labels
                ForEach(Array(Self.hashMarks.enumerated()), id: \.offset) { _, mark in
                    let markY = height - (mark.position * height)

                    // Hash line extending from the bar to the left
                    Rectangle()
                        .fill(Theme.white.opacity(0.75))
                        .frame(width: 15, height: 1)
                        .position(x: barX + 8, y: markY)

                    // dB label
                    Text(mark.label)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.white.opacity(0.75))
                        .position(x: barX + 20, y: markY)
                }
            }
            .frame(width: width, height: height)
        }
        .animation(.linear(duration: 0.05), value: level)
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
            peak: 0.85,
            isExternalMic: true,
            isRecording: true
        )
        .frame(width: 50, height: 200)

        VUMeterView(
            level: 0.5,
            peak: 0.6,
            isExternalMic: false,
            isRecording: false
        )
        .frame(width: 50, height: 200)
    }
    .padding()
    .background(Color.black)
}
