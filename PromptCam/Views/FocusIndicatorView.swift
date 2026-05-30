// May 29, 2026 - 11:23pm - GitHub Copilot
import SwiftUI

struct FocusIndicatorView: View {
    let exposureRange: Float
    let exposureBias: Float
    let showFocusIndicator: Bool
    let onDragDelta: (CGFloat) -> Void
    let onLongPressToggleLock: () -> Void

    private var biasClamped: Float { min(max(exposureBias, -exposureRange), exposureRange) }

    var body: some View {
        let boxSize: CGFloat = 84
        let cornerLength: CGFloat = 16
        let lineWidth: CGFloat = 2
        let sliderHeight: CGFloat = 110
        let sliderOffsetX: CGFloat = (boxSize / 2) + 16
        let sliderTravel = Float(sliderHeight / 2 - 8)
        let sunOffsetY = CGFloat(-biasClamped / exposureRange * sliderTravel)
        let evText = String(format: "%.1f", biasClamped)

        return ZStack {
            FocusCorners(size: boxSize, cornerLength: cornerLength, lineWidth: lineWidth)

            if showFocusIndicator {
                Rectangle()
                    .fill(Theme.yellow)
                    .frame(width: lineWidth, height: sliderHeight)
                    .offset(x: sliderOffsetX, y: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .font(Theme.icon20)
                    .foregroundStyle(Theme.yellow)

                Text("EV \(evText)")
                    .font(Theme.mono10Medium)
                    .foregroundStyle(Theme.yellow)
                    .frame(width: 52, alignment: .leading)
            }
            .offset(x: sliderOffsetX + 29, y: sunOffsetY)
        }
        .frame(width: boxSize, height: boxSize)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onDragDelta(value.translation.height)
                }
        )
        .onLongPressGesture(minimumDuration: 1.2) {
            onLongPressToggleLock()
        }
        .accessibilityLabel("Exposure and focus control")
        .accessibilityHint("Drag up or down to adjust exposure. Long press to toggle focus and exposure lock.")
    }
}

private struct FocusCorners: View {
    let size: CGFloat
    let cornerLength: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        let half = size / 2
        ZStack {
            Rectangle()
                .fill(Theme.yellow)
                .frame(width: cornerLength, height: lineWidth)
                .offset(x: -half + cornerLength / 2, y: -half + lineWidth / 2)
            Rectangle()
                .fill(Theme.yellow)
                .frame(width: lineWidth, height: cornerLength)
                .offset(x: -half + lineWidth / 2, y: -half + cornerLength / 2)
            Rectangle()
                .fill(Theme.yellow)
                .frame(width: cornerLength, height: lineWidth)
                .offset(x: half - cornerLength / 2, y: -half + lineWidth / 2)
            Rectangle()
                .fill(Theme.yellow)
                .frame(width: lineWidth, height: cornerLength)
                .offset(x: half - lineWidth / 2, y: -half + cornerLength / 2)

            Rectangle()
                .fill(Theme.yellow)
                .frame(width: cornerLength, height: lineWidth)
                .offset(x: -half + cornerLength / 2, y: half - lineWidth / 2)
            Rectangle()
                .fill(Theme.yellow)
                .frame(width: lineWidth, height: cornerLength)
                .offset(x: -half + lineWidth / 2, y: half - cornerLength / 2)

            Rectangle()
                .fill(Theme.yellow)
                .frame(width: cornerLength, height: lineWidth)
                .offset(x: half - cornerLength / 2, y: half - lineWidth / 2)
            Rectangle()
                .fill(Theme.yellow)
                .frame(width: lineWidth, height: cornerLength)
                .offset(x: half - lineWidth / 2, y: half - cornerLength / 2)
        }
    }
}
