// June 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - EV adjustment panel with hash marks
// June 8, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Fix reset: use absolute setExposure(to:) via onReset
// June 17, 2026 - Refactored to use StandardPanel for consistent UI.
import SwiftUI

/// Panel for live exposure value adjustment.
/// Changes are live (no confirm needed). "Reset" returns to neutral (EV 0).
///
/// Uses `StandardPanel` for consistent panel chrome.
struct EVAdjustmentPanel: View {
    @Binding var exposureBias: Float
    let exposureRange: Float
    let onReset: () -> Void
    let onAdjust: (Float) -> Void
    let onDismiss: () -> Void

    var body: some View {
        StandardPanel(
            title: "EV Bias",
            icon: "sun.max.fill",
            autoDismissAfter: 12,
            onDismiss: onDismiss
        ) {
            VStack(alignment: .leading, spacing: Theme.space16) {
                EVSliderRow(
                    exposureBias: $exposureBias,
                    exposureRange: exposureRange,
                    onAdjust: onAdjust
                )
                HStack{
                    Spacer()
                    ResetButton(onReset: {
                        exposureBias = 0
                        onReset()
                    })
                    Spacer()
                }
            }
        }
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
                    .foregroundStyle(Theme.primaryText)

                Spacer()

                Text(valueLabel)
                    .font(Theme.mono16Medium)
                    .foregroundStyle(Theme.accent)
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
            .tint(Theme.accent)

            // Hash marks at -max, 0, +max
            HStack {
                Rectangle()
                    .fill(Theme.primaryText.opacity(0.5))
                    .frame(width: 1, height: 6)

                Spacer()

                Rectangle()
                    .fill(Theme.primaryText)
                    .frame(width: 1, height: 6)

                Spacer()

                Rectangle()
                    .fill(Theme.primaryText.opacity(0.5))
                    .frame(width: 1, height: 6)
            }
            .padding(.top, 2)

            // Min/Center/Max labels
            HStack {
                Text("\(String(format: "%.0f", -exposureRange))")
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.primaryText)

                Spacer()

                Text("0")
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.primaryText)

                Spacer()

                Text("+\(String(format: "%.0f", exposureRange))")
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.primaryText)
            }
        }
    }
}

// MARK: - Reset Button

private struct ResetButton: View {
    let onReset: () -> Void

    var body: some View {
        Button(action: onReset) {
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
        .accessibilityLabel("Reset EV Bias")
        .accessibilityHint("Returns to neutral automatic exposure")
    }
}
