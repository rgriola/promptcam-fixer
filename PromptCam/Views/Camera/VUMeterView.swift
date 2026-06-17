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
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            // Top padding reserves space for the source icon.
            let topPad: CGFloat = micIconSize + Theme.space4
            let barHeight = height - topPad

            // Bar occupies the left ~55% of width; right side holds dB labels.
            let barWidth = floor(width * 0.55)
            let barCenterX = barWidth / 2
            let labelGap: CGFloat = 4      // gap between bar right edge and label
            let labelX = barWidth + labelGap
            let labelWidth = max(width - labelX, 0)

            let clampedLevel = CGFloat(min(max(level, 0), 1))
            let clampedPeak  = CGFloat(min(max(peak,  0), 1))
            let fillHeight = clampedLevel * barHeight
            let peakY = topPad + barHeight - (clampedPeak * barHeight)

            ZStack {
                // Source icon — always visible above the bar
                Image(systemName: isExternalMic ? "mic.fill" : "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: micIconSize, weight: .semibold))
                    .foregroundStyle(isExternalMic ? Theme.purple : Theme.secondaryText)
                    .position(x: barCenterX, y: micIconSize / 2)
                    .transition(.opacity)

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
                                    .init(color: vuGreen,  location: 0.0),
                                    .init(color: vuGreen,  location: 0.6),
                                    .init(color: vuYellow, location: 0.6),
                                    .init(color: vuYellow, location: 0.8),
                                    .init(color: vuRed,    location: 0.8),
                                    .init(color: vuRed,    location: 1.0),
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

                    // Tick spans exactly the bar width — no overhang
                    Rectangle()
                        .fill(Theme.white.opacity(0.6))
                        .frame(width: barWidth, height: 1)
                        .position(x: barCenterX, y: markY)

                    // dB label right-aligned in the space right of the bar
                    Text(mark.label)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.white.opacity(0.75))
                        .frame(width: labelWidth + 10, alignment: .leading)
                        .position(x: (labelX + labelWidth / 2) + 5, y: markY)
                }
            }
            .frame(width: width, height: height)
        }
        .animation(.linear(duration: 0.05), value: level)
        .animation(.easeInOut(duration: 0.25), value: isRecording)
        .animation(.easeInOut(duration: 0.3), value: isExternalMic)
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
