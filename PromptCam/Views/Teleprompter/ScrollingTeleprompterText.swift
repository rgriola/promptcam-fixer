// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Extracted from TeleprompterOverlayView (Phase 4)
import SwiftUI

/// Renders the teleprompter script text at a given vertical offset.
/// Horizontal padding and font are driven by Theme constants so the
/// rendered width exactly matches the UIKit measurement in TeleprompterMeasurement.
struct ScrollingTeleprompterText: View {
    let text: String
    let fontSize: Double
    let textColor: Color
    let offsetY: CGFloat

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(Theme.fontFamily.rounded(size: fontSize, weight: .semibold))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.teleprompterHPad) // Must stay in sync with TeleprompterMeasurement.
                .padding(.vertical, Theme.space16)
                .frame(width: geo.size.width, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                // Position the text block so its top edge is at offsetY.
                // .position places the view's CENTER, so we shift by half the view's height.
                .offset(y: offsetY)
                // Anchor the text's top-left to the viewport's top-left,
                // then let .offset handle the scroll position.
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .clipped()
    }
}
