// June 14, 2026 - GitHub Copilot (Claude Sonnet 4.6)
// June 17, 2026 - Refactored to use StandardPanel for consistent UI.
// Cinematic aperture (f-stop) control panel.
// Requires iOS 26+ for AVCaptureDeviceInput.simulatedAperture. On older OS,
// the ViewModel never sets cinematicApertureRange so this panel is never shown.
import SwiftUI

/// Panel for adjusting the simulated aperture (f-stop) in cinematic mode.
/// A lower f-stop means wider aperture and more background blur.
/// Changes are live (no confirm needed). "Default" resets to the format default.
///
/// Uses `StandardPanel` for consistent panel chrome.
struct CinematicAperturePanel: View {
    @Binding var aperture: Float
    let apertureRange: ClosedRange<Float>
    let defaultAperture: Float
    let onReset: () -> Void
    let onAdjust: (Float) -> Void
    let onDismiss: () -> Void

    var body: some View {
        StandardPanel(
            title: "Aperture",
            icon: "camera.aperture",
            autoDismissAfter: 12,
            onDismiss: onDismiss
        ) {
            VStack(alignment: .leading, spacing: Theme.space16) {
                ApertureSliderRow(
                    aperture: $aperture,
                    apertureRange: apertureRange,
                    onAdjust: onAdjust
                )
                HStack{
                    Spacer()
                    DefaultButton(onReset: {
                        aperture = defaultAperture
                        onReset()
                        })
                    Spacer()
                }
            }
        }
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
                Text("f-Stop")
                    .font(Theme.font16Medium)
                    .foregroundStyle(Theme.primaryText)

                Spacer()

                Text(valueLabel)
                    .font(Theme.mono16Medium)
                    .foregroundStyle(Theme.accent)
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
            .tint(Theme.accent)

            // Hash marks at min, mid, max
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

            HStack {
                Text(String(format: "f/%.1f", apertureRange.lowerBound))
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.primaryText)

                Spacer()

                Text(String(format: "f/%.1f", (apertureRange.lowerBound + apertureRange.upperBound) / 2))
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.primaryText)

                Spacer()

                Text(String(format: "f/%.1f", apertureRange.upperBound))
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.primaryText)
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
                Text("Reset")
                    .font(Theme.font12Regular)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, Theme.space12)
            .padding(.vertical, 6)
            .background(Theme.white.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}
