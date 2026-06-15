// June 14, 2026 - GitHub Copilot (Claude Sonnet 4.6)
// Cinematic aperture (f-stop) control panel — mirrors EVAdjustmentPanel layout.
// Requires iOS 26+ for AVCaptureDeviceInput.simulatedAperture. On older OS,
// the ViewModel never sets cinematicApertureRange so this panel is never shown.
import SwiftUI

/// Slide-down panel for adjusting the simulated aperture (f-stop) in cinematic mode.
/// A lower f-stop means wider aperture and more background blur.
/// Changes are live (no confirm needed). "Default" button resets to the format default.
struct CinematicAperturePanel: View {
    @Binding var aperture: Float
    let apertureRange: ClosedRange<Float>
    let defaultAperture: Float
    let onReset: () -> Void
    let onAdjust: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space16) {
            ApertureSliderRow(
                aperture: $aperture,
                apertureRange: apertureRange,
                onAdjust: onAdjust
            )

            DefaultButton(onReset: {
                aperture = defaultAperture
                onReset()
            })
        }
        .padding(Theme.space12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
    }
}

// MARK: - Aperture Slider Row

private struct ApertureSliderRow: View {
    @Binding var aperture: Float
    let apertureRange: ClosedRange<Float>
    let onAdjust: (Float) -> Void

    var valueLabel: String {
        String(format: "f/%.1f", aperture)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            HStack {
                Text("Aperture")
                    .font(Theme.font16Medium)
                    .foregroundStyle(Theme.blackText)

                Spacer()

                Text(valueLabel)
                    .font(Theme.mono16Medium)
                    .foregroundStyle(Theme.blackText)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(aperture) },
                    set: { newValue in
                        let newAp = Float(newValue)
                        aperture = newAp
                        onAdjust(newAp)
                    }
                ),
                in: Double(apertureRange.lowerBound)...Double(apertureRange.upperBound),
                step: 0.1
            )
            .controlSize(.large)
            .tint(Theme.blue)

            // Hash marks at min, mid, max
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

            HStack {
                Text(String(format: "f/%.1f", apertureRange.lowerBound))
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.secondaryText)

                Spacer()

                Text(String(format: "f/%.1f", (apertureRange.lowerBound + apertureRange.upperBound) / 2))
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.secondaryText)

                Spacer()

                Text(String(format: "f/%.1f", apertureRange.upperBound))
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// MARK: - Default Button

private struct DefaultButton: View {
    let onReset: () -> Void

    var body: some View {
        Button(action: onReset) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(Theme.font12Regular)
                Text("Default")
                    .font(Theme.font12Regular)
            }
            .foregroundStyle(Theme.blackText)
            .padding(.horizontal, Theme.space8)
            .padding(.vertical, 6)
            .background(Theme.white.opacity(0.25))
            .clipShape(Capsule())
        }
    }
}
