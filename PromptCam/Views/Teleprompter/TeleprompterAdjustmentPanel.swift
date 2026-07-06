// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Phase 5: teleprompter adjustment panel
// June 17, 2026 - Refactored to use StandardPanel for consistent UI.
import SwiftUI

/// Panel for live teleprompter style adjustments.
/// Changes are live (no confirm needed). Caller is responsible for persisting
/// via `updateTeleprompterStyle(_:)` on the ViewModel.
///
/// Uses `StandardPanel` for consistent panel chrome.
struct TeleprompterAdjustmentPanel: View {
    @Binding var config: TeleprompterConfig
    let onReset: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        StandardPanel(
            title: "Prompter",
            icon: "text.viewfinder",
            autoDismissAfter: nil,  // Stays open — user is actively adjusting
            onDismiss: onDismiss
        ) {
            VStack(alignment: .leading, spacing: Theme.space16) {
                // MARK: Font Size
                SliderRow(
                    label: "Size",
                    valueLabel: "\(Int(config.fontSize))pt",
                    value: Binding(
                        get: { config.fontSize },
                        set: { config.fontSize = round($0 / 2) * 2 } // snap to even
                    ),
                    range: 24...50,
                    step: 2
                )
                // MARK: Scroll Speed
                SliderRow(
                    label: "Speed",
                    valueLabel: "\(Int(config.speedPointsPerSecond))/s",
                    value: $config.speedPointsPerSecond,
                    range: 20...80,
                    step: 1
                )
                // MARK: Text - Background Contrast 
                SliderRow(
                    label: "Contrast",
                    valueLabel: "\(Int(config.backgroundOpacity * 100))%",
                    value: $config.backgroundOpacity,
                    range: 0...0.30,
                    step: 0.01
                )

                // MARK: Text Color
                HStack(spacing: 0) {
                    Text("Color")
                        .font(Theme.font16Medium)
                        .foregroundStyle(Theme.primaryText)
                        .frame( width: 90, 
                                alignment: .leading)
                    
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
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(Theme.font12Regular)
                            Text("Reset")
                                .font(Theme.font12Regular)
                        }
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, Theme.space12)
                        .padding(.vertical, 6)
                        .background(Theme.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    Spacer()
                }
            }
        }
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
                .foregroundStyle(Theme.primaryText)
                .frame(width: 90, alignment: .leading)

            Slider(value: $value, in: range, step: step)
                .controlSize(.large)
                .tint(Theme.accent)

            Text(valueLabel)
                .font(Theme.font16Medium)
                .foregroundStyle(Theme.accent)
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
                            .stroke(isSelected ? Theme.accent : Theme.glassBorder, lineWidth: isSelected ? 2 : 1)
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
