// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Extracted from TeleprompterOverlayView (Phase 4)
import SwiftUI

/// Diagnostic overlay showing live teleprompter geometry values.
/// Enabled only when `kTeleprompterDebugHUD` is true — zero production impact.
struct TeleprompterDebugHUD: View {
    let config: TeleprompterConfig
    let measuredTextHeight: CGFloat
    let manualOffset: CGFloat
    let isScrolling: Bool
    let scrollStartTime: Date
    let viewportH: CGFloat
    let date: Date

    var body: some View {
        let geo = TeleprompterGeometry(
            viewportHeight: viewportH,
            textHeight: max(measuredTextHeight, 1),
            fontSize: CGFloat(config.fontSize),
            verticalPadding: Theme.space16
        )
        let elapsed = date.timeIntervalSince(scrollStartTime)
        let autoOff = isScrolling ? -elapsed * config.speedPointsPerSecond : 0
        let rendered = min(max(geo.startOffset + manualOffset + autoOff, geo.scrollStopOffset), geo.dragCeiling)
        VStack(alignment: .leading, spacing: 2) {
            Text("TP-DEBUG").foregroundStyle(.red)
            Text("viewportH: \(Int(viewportH))")
            Text("textH:     \(Int(measuredTextHeight))")
            Text("textLen:   \(config.text.count)")
            Text("offset:    \(Int(rendered))")
            Text("manual:    \(Int(manualOffset))")
            Text("start:     \(Int(geo.startOffset))")
            Text("floor:     \(Int(geo.scrollStopOffset))")
            Text("ceiling:   \(Int(geo.dragCeiling))")
            Text("scrolling: \(isScrolling ? "YES" : "no")")
            Text("speed:     \(Int(config.speedPointsPerSecond))")
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(.yellow)
        .padding(8)
        .background(Color.black.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red, lineWidth: 1)
        )
        .cornerRadius(6)
        .padding(8)
    }
}
