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

    private let micIconSize: CGFloat = 20
    private let channelGap: CGFloat  = 3   // gap between Ch1 and Ch2 bars in stereo mode

    /// dB hash mark positions: (normalized 0–1 position, label string).
    /// Derived from normalizeDecibels: dB → (dB + 60) / 60
    private static let hashMarks: [(position: CGFloat, label: String)] = [
        (1.0,   " 0"),     // 0 dB   — clipping
        (0.9,   "-6"),    // -6 dB
        (0.8,   "-12"),   // -12 dB
        (0.667, "-20"),   // -20 dB
        (0.5,   "-30"),   // -30 dB
        (0.333, "-40"),   // -40 dB
    ]

    // MARK: - Body

    var body: some View {
        let isStereo = level2 != nil

        VStack(spacing: 2) {
            // ── Icon Row ── fixed intrinsic height
            iconRow(isStereo: isStereo)
                .frame(height: micIconSize)
                .padding(.top, 8)
                .padding(.bottom, 8)

            // ── Meter Area ── fills remaining space
            GeometryReader { geo in
                let barColumnFraction: CGFloat = 0.50
                let barColumnWidth = floor(geo.size.width * barColumnFraction)
                let barHeight = geo.size.height

                let singleBarWidth: CGFloat = isStereo
                    ? floor((barColumnWidth - channelGap) / 2)
                    : barColumnWidth

                HStack(spacing: 0) {
                    // Left: bar column (Ch1, optional Ch2, hash marks)
                    ZStack(alignment: .bottom) {
                        // Ch1 bar
                        VUBarView(
                            level: level,
                            peak: peak,
                            isRecording: isRecording
                            )
                            .frame(width: singleBarWidth)

                        // Ch2 bar (stereo only)
                        if let l2 = level2, let p2 = peak2 {
                            VUBarView(
                                level: l2,
                                peak: p2,
                                isRecording: isRecording
                            )
                            .frame(width: singleBarWidth)
                            .offset(x: singleBarWidth + channelGap)
                        }
                    }
                    .frame(
                        width: barColumnWidth,
                        height: barHeight,
                        alignment: .leading
                        )
                        .overlay {
                            // Hash mark lines span the bar column
                            hashMarkOverlay(
                                barHeight: barHeight,
                                barColumnWidth: barColumnWidth
                                )
                        }

                    // Right: dB labels
                    labelColumn(barHeight: barHeight)
                }
            }
        }
        .clipped()
        .animation(.linear(duration: 0.05),    value: level)
        .animation(.linear(duration: 0.05),    value: level2)
        .animation(Theme.easeInOut3,  value: isRecording)
        .animation(Theme.easeInOut3,  value: isExternalMic)
        .animation(.easeInOut(duration: 0.25), value: sourceNameHint)
        .animation(.easeInOut(duration: 0.4),  value: level2 != nil)
    }

    // MARK: - Extracted Sub-views

    /// Top icon row: mic icon (mono) or channel labels "1"/"2" (stereo).
    @ViewBuilder
    private func iconRow(isStereo: Bool) -> some View {
        if isStereo {

            VStack{

                 Image(systemName: "microphone.fill")
                    .font(.system(size: micIconSize, weight: .semibold))
                    .foregroundStyle(Theme.white)

                HStack{
                    Text("1")
                        .font(Theme.mono08)
                        .foregroundStyle(Theme.white)
                        //.frame(maxWidth: .infinity)
                    Text("2")
                        .font(Theme.mono08)
                        .foregroundStyle(Theme.white)
                       // .frame(maxWidth: .infinity)
                    
                    Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    //.padding(.bottom, 4)
            }

        } else {
            Image(systemName: isExternalMic
                  ? "airpods.pro"
                  : "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: micIconSize, weight: .semibold))
                .foregroundStyle(Theme.white)
                .padding(.bottom, 8)
        }
    }

    /// Hash mark lines + dB labels overlay for the bar column.
    private func hashMarkOverlay(barHeight: CGFloat, barColumnWidth: CGFloat) -> some View {
        ZStack {
            ForEach(Array(Self.hashMarks.enumerated()), id: \.offset) { _, mark in
                let offsetY = barHeight / 2 - (mark.position * barHeight)

                Rectangle()
                    .fill(Theme.white.opacity(0.8))
                    .frame(width: barColumnWidth, height: 1)
                    .offset(y: offsetY)
            }
        }
    }

    /// dB label column on the right side of the meter.
    private func labelColumn(barHeight: CGFloat) -> some View {
        ZStack {
            ForEach(
                Array(
                    Self.hashMarks.enumerated()
                    ), 
                    id: \.offset
                    ) 
            { _, mark in
                let offsetY = barHeight / 2 - (mark.position * barHeight)

                Text(mark.label)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.white.opacity(0.8))
                    .offset(y: offsetY)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - VUBarView

/// A single vertical bar — gradient fill, peak hold line, CLIP latch,
/// and no-signal dim. Fills the frame given by its parent; no absolute
/// positioning needed.
private struct VUBarView: View {
    let level: Float
    let peak: Float
    let isRecording: Bool

    private let peakLineHeight: CGFloat = 2
    private let clipThreshold: Float    = 0.98
    private let noSignalThreshold: Float = 0.03
    private let noSignalGracePeriod: TimeInterval = 2.0
    private let clipLatchDuration: TimeInterval   = 1.0

    @State private var clipLatched: Bool = false
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
        // Levels arrive ~30x/sec, faster than SwiftUI draws. Reducing them to
        // booleans first means the observers below fire only on transitions.
        let isClipping = peak >= clipThreshold
        let hasSignal = level >= noSignalThreshold

        GeometryReader { geo in
            let barHeight = geo.size.height
            let clampedLevel = CGFloat(min(max(level, 0), 1))
            let clampedPeak  = CGFloat(min(max(peak,  0), 1))
            let fillHeight   = clampedLevel * barHeight
            let peakOffset   = clampedPeak * barHeight

            let meterOpacity: Double = isNoSignal ? 0.4 : 1.0

            ZStack(alignment: .bottom) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.panelBg.opacity(0.4))

                // Level fill — gradient rises from bottom
                RoundedRectangle(cornerRadius: 4)
                    .fill(Self.levelGradient)
                    .frame(height: fillHeight)

                // Peak hold line
                Rectangle()
                    .fill(Theme.accent.opacity(0.9))
                    .frame(height: peakLineHeight)
                    .offset(y: -peakOffset)
                    .animation(.linear(duration: 0.05), value: peak)
            }
            .opacity(meterOpacity)
            .overlay(alignment: .top) {
                // CLIP badge at top of bar
                if clipLatched {
                    Text("CLIP")
                        .font(
                            .system(
                                size: 8, 
                                weight: .heavy, 
                                design: .monospaced
                                )
                            )
                        .foregroundStyle(Theme.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Theme.red, in: RoundedRectangle(cornerRadius: 2))
                        .offset(y: -12)
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording { isNoSignal = false }
        }
        .task(id: isClipping) {
            // Latch while clipping, then hold the badge for a beat after it stops.
            if isClipping {
                clipLatched = true
                return
            }
            guard clipLatched else { return }
            try? await Task.sleep(for: .seconds(clipLatchDuration))
            guard !Task.isCancelled else { return }
            clipLatched = false
        }
        .task(id: hasSignal) {
            if hasSignal {
                isNoSignal = false
                return
            }
            try? await Task.sleep(for: .seconds(noSignalGracePeriod))
            guard !Task.isCancelled else { return }
            if !isRecording { isNoSignal = true }
        }
        .animation(.easeInOut(duration: 0.25), value: clipLatched)
        .animation(Theme.easeInOut3,  value: isRecording)
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
