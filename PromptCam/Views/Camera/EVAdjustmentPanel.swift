// June 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - EV adjustment panel with hash marks
import SwiftUI

/// Slide-down panel for live exposure value adjustment.
/// Positioned below the EV button in the camera header.
/// Changes are live (no confirm needed). "Auto" button returns to neutral (EV 0).
struct EVAdjustmentPanel: View {
    @Binding var exposureBias: Float
    let exposureRange: Float
    let onReset: () -> Void
    let onAdjust: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space16) {
            EVSliderRow(
                exposureBias: $exposureBias,
                exposureRange: exposureRange,
                onAdjust: onAdjust
            )
            
            AutoButton(onReset: onReset)
        }
        .padding(Theme.space12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
    }
}

// MARK: - EV Slider Row

private struct EVSliderRow: View {
    @Binding var exposureBias: Float
    let exposureRange: Float
    let onAdjust: (Float) -> Void

    var valueLabel: String {
        let sign = exposureBias >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", exposureBias))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            // EV label + current value
            HStack {
                Text("EV")
                    .font(Theme.font16Medium)
                    .foregroundStyle(Theme.blackText)

                Spacer()

                Text(valueLabel)
                    .font(Theme.mono16Medium)
                    .foregroundStyle(Theme.blackText)
                    .monospacedDigit()
            }

            // Slider
            Slider(
                value: Binding(
                    get: { Double(exposureBias) },
                    set: { newValue in
                        let newBias = Float(newValue)
                        exposureBias = newBias
                        onAdjust(newBias)
                    }
                ),
                in: Double(-exposureRange)...Double(exposureRange),
                step: 0.1
            )
            .controlSize(.large)
            .tint(Theme.blue)

            // Hash marks at -5, 0, +5
            HStack {
                Rectangle()
                    .fill(Theme.secondaryText)
                    .frame(width: 1, height: 6)
                
                Spacer()
                
                Rectangle()
                    .fill(Theme.blackText)
                    .frame(width: 1, height: 6)
                
                Spacer()
                
                Rectangle()
                    .fill(Theme.secondaryText)
                    .frame(width: 1, height: 6)
            }
            .padding(.top, 2)
            
            // Min/Center/Max labels
            HStack {
                Text("\(String(format: "%.0f", -exposureRange))")
                    .font(Theme.font10Regular)
                    .foregroundStyle(Theme.blackText)

                Spacer()

                Text("0")
                    .font(Theme.font10Medium)
                    .foregroundStyle(Theme.blackText)

                Spacer()

                Text("+\(String(format: "%.0f", exposureRange))")
                    .font(Theme.font10Regular)
                    .foregroundStyle(Theme.blackText)
            }
        }
    }
}

// MARK: - Auto Button

private struct AutoButton: View {
    let onReset: () -> Void

    var body: some View {
        Button(action: onReset) {
            Text("Reset")
                .font(Theme.font16Medium)
                .foregroundStyle(Theme.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.space8)
                .background(Theme.glassOverlay, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
        }
        .accessibilityLabel("Reset EV Bias")
        .accessibilityHint("Returns to neutral automatic exposure")
    }
}
