// June 14, 2026 - GitHub Copilot (Claude Sonnet 4.6)
// June 17, 2026 - Restyled to match AudioSourcePickerView panel design.
// Cinematic aperture (f-stop) control panel.
// Requires iOS 26+ for AVCaptureDeviceInput.simulatedAperture. On older OS,
// the ViewModel never sets cinematicApertureRange so this panel is never shown.
import SwiftUI

/// Slide-in panel for adjusting the simulated aperture (f-stop) in cinematic mode.
/// A lower f-stop means wider aperture and more background blur.
/// Changes are live (no confirm needed). "Default" resets to the format default.
///
/// Styled to match `AudioSourcePickerView` — dark glass panel with header,
/// close button, and auto-dismiss after 12 seconds of inactivity.
struct CinematicAperturePanel: View {
    @Binding var aperture: Float
    let apertureRange: ClosedRange<Float>
    let defaultAperture: Float
    let onReset: () -> Void
    let onAdjust: (Float) -> Void
    let onDismiss: () -> Void

    /// Seconds before the panel auto-dismisses if the user takes no action.
    private let autoDismissAfter: TimeInterval = 12

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Aperture")
                    .font(Theme.font16Semibold)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, Theme.space16)
            .padding(.vertical, Theme.space12)

            Divider()
                .overlay(Theme.separator)

            // Content
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
            .padding(Theme.space16)
        }
        .background(Theme.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLg)
                .strokeBorder(Theme.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .task {
            try? await Task.sleep(for: .seconds(autoDismissAfter))
            guard !Task.isCancelled else { return }
            onDismiss()
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
                    .fill(Theme.secondaryText.opacity(0.5))
                    .frame(width: 1, height: 6)

                Spacer()

                Rectangle()
                    .fill(Theme.secondaryText)
                    .frame(width: 1, height: 6)

                Spacer()

                Rectangle()
                    .fill(Theme.secondaryText.opacity(0.5))
                    .frame(width: 1, height: 6)
            }
            .padding(.top, 2)

            HStack {
                Text(String(format: "f/%.1f", apertureRange.lowerBound))
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.tertiaryText)

                Spacer()

                Text(String(format: "f/%.1f", (apertureRange.lowerBound + apertureRange.upperBound) / 2))
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.tertiaryText)

                Spacer()

                Text(String(format: "f/%.1f", apertureRange.upperBound))
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.tertiaryText)
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
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, Theme.space12)
            .padding(.vertical, 6)
            .background(Theme.white.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}
