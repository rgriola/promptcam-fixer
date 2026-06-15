// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Phase 5: teleprompter adjustment panel
import SwiftUI

/// Slide-up panel for live teleprompter style adjustments.
/// Spans the full screen width. Positioned above the footer controls,
/// below the teleprompter viewport — never covers the script.
/// Changes are live (no confirm needed). Caller is responsible for persisting
/// via `updateTeleprompterStyle(_:)` on the ViewModel.
struct TeleprompterAdjustmentPanel: View {
    @Binding var config: TeleprompterConfig
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space16) {


            // MARK: Font Size
            SliderRow(
                label: "Size",
                valueLabel: "\(Int(config.fontSize))pt",
                value: Binding(
                    get: { config.fontSize },
                    set: { config.fontSize = round($0 / 2) * 2 } // snap to even
                ),
                range: 16...72,
                step: 2
            )
            // MARK: Scroll Speed
            SliderRow(
                label: "Speed",
                valueLabel: "\(Int(config.speedPointsPerSecond))/s",
                value: $config.speedPointsPerSecond,
                range: 5...150,
                step: 1
            )
            // MARK: Background Opacity
            SliderRow(
                label: "Opacity",
                valueLabel: "\(Int(config.backgroundOpacity * 100))%",
                value: $config.backgroundOpacity,
                range: 0...0.30,
                step: 0.01
            )

            // MARK: Text Color
            HStack(spacing: 0) {
                Text("Color")
                    .font(Theme.font16Medium)
                    .foregroundStyle(Theme.blackText)
                    .frame(width: 90, alignment: .leading)

                Spacer()

                HStack(spacing: Theme.space12) {
                    ForEach(TeleprompterTextColor.allCases, id: \.self) { preset in
                        ColorSwatchButton(
                            preset: preset,
                            isSelected: config.textColor == preset,
                            onTap: {
                                config.textColor = preset
                                Log.teleprompter.debug("textColor -> \(preset.rawValue, privacy: .public)")
                            }
                        )
                    }
                }
            }

            // MARK: Reset
            HStack {
                Spacer()
                Button(action: {
                    onReset()
                    Log.teleprompter.debug("AdjustmentPanel reset tapped")
                }) {
                    Text("Reset")
                        .font(Theme.font16Medium)
                        .foregroundStyle(Theme.blue)
                        .frame(width: 90)
                        .padding(.vertical, Theme.space8)
                        .background(Theme.glassOverlay, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
                }
                Spacer()
            }
        }
        .padding(Theme.space16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .padding(.horizontal, Theme.space8)
        .padding(.bottom, Theme.space8)
    }
}

// MARK: - Slider Row

private struct SliderRow: View {
    let label: String
    let valueLabel: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(Theme.font16Medium)
                .foregroundStyle(Theme.blackText)
                .frame(width: 90, alignment: .leading)

            Slider(value: $value, in: range, step: step)
            .controlSize(.large)
                .tint(Theme.blue)

            Text(valueLabel)
                .font(Theme.font16Medium)
                .foregroundStyle(Theme.blackText)
                .frame(width: 48, alignment: .trailing)
                .monospacedDigit()
        }
    }
}

// MARK: - Color Swatch Button

private struct ColorSwatchButton: View {
    let preset: TeleprompterTextColor
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(preset.color)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Theme.blue : Theme.glassBorder, lineWidth: isSelected ? 2 : 1)
                    )
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(preset == .white || preset == .yellow ? Theme.black : Theme.white)
                }
            }
        }
        .accessibilityLabel(preset.label)
    }
}
