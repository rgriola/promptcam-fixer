import SwiftUI

/// A vertical VU (audio level) meter that displays real-time audio levels
/// with a three-color gradient fill, peak hold indicator, and dB tick marks.
struct VUMeterView: View {
    let level: Float
    let peak: Float
    let isExternalMic: Bool
    let isRecording: Bool

    // MARK: - Constants

    private let barWidth: CGFloat = 8
    private let peakLineHeight: CGFloat = 2
    private let tickLength: CGFloat = 4
    private let micIconSize: CGFloat = 12

    /// dB tick positions expressed as linear 0-1 values.
    /// 0 dB → 1.0, -6 dB → 0.5, -12 dB → 0.25, -20 dB → 0.1
    private let dbTicks: [CGFloat] = [1.0, 0.5, 0.25, 0.1]

    // MARK: - Gradient colors

    private let vuGreen = Color(hex: "#34C759")
    private let vuYellow = Color(hex: "#FFD60A")
    private let vuRed = Color(hex: "#FF3B30")

    // MARK: - Body

    var body: some View {
        VStack(spacing: Theme.space4) {
            // External mic indicator
            if isExternalMic {
                Image(systemName: "mic.fill")
                    .font(.system(size: micIconSize))
                    .foregroundStyle(Theme.purple)
                    .transition(.opacity)
            }

            // Meter bar
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
            let clampedLevel = CGFloat(min(max(level, 0), 1))
            let clampedPeak = CGFloat(min(max(peak, 0), 1))
            let fillHeight = clampedLevel * height
            let peakY = height - (clampedPeak * height)

            ZStack(alignment: .bottom) {
                // Background track
                RoundedRectangle(cornerRadius: Theme.radiusSm)
                    .fill(Theme.panelBg.opacity(0.3))

                // Filled portion (gradient from bottom)
                RoundedRectangle(cornerRadius: Theme.radiusSm)
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
                    .frame(height: fillHeight)

                // Peak hold indicator
                Rectangle()
                    .fill(Theme.white.opacity(0.8))
                    .frame(width: barWidth, height: peakLineHeight)
                    .position(x: barWidth / 2, y: peakY)
                    .animation(.linear(duration: 0.05), value: peak)

                // dB tick marks (right side)
                ForEach(Array(dbTicks.enumerated()), id: \.offset) { _, tick in
                    let tickY = height - (tick * height)
                    Rectangle()
                        .fill(Theme.white.opacity(0.2))
                        .frame(width: tickLength, height: 1)
                        .position(x: barWidth - tickLength / 2, y: tickY)
                }
            }
            .frame(width: barWidth, height: height)
        }
        .frame(width: barWidth)
        .animation(.linear(duration: 0.05), value: level)
    }
}

// MARK: - Preview

#Preview("VU Meter") {
    HStack(spacing: 16) {
        VUMeterView(
            level: 0.3,
            peak: 0.5,
            isExternalMic: false,
            isRecording: true
        )
        .frame(height: 120)

        VUMeterView(
            level: 0.7,
            peak: 0.85,
            isExternalMic: true,
            isRecording: true
        )
        .frame(height: 120)

        VUMeterView(
            level: 0.5,
            peak: 0.6,
            isExternalMic: false,
            isRecording: false
        )
        .frame(height: 120)
    }
    .padding()
    .background(Color.black)
}
