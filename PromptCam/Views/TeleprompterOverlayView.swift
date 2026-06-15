// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Phase 4: extract ScrollingTeleprompterText, TeleprompterMeasurement, TeleprompterDebugHUD
// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add edge-fade mask and eyeline triangle indicator
import SwiftUI
import os

/// Diagnostic HUD overlay. Keep off for normal use; flip true while debugging offset math.
private let kTeleprompterDebugHUD = false
// Horizontal padding applied to both the SwiftUI render and the UIKit measurement.
// Single lever — change Theme.teleprompterHPad to adjust text column width.

@inline(__always)
private func tp(_ msg: @autoclosure () -> String) {
    let m = msg()
    Log.teleprompter.debug("\(m, privacy: .public)")
}

struct TeleprompterOverlayView: View {
    let config: TeleprompterConfig
    let isScrolling: Bool
    /// Bumped by the ViewModel to signal a position reset (zero manualOffset).
    let resetToken: Int
    let onTextHeightChanged: (CGFloat) -> Void

    @State private var measuredTextHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    @GestureState private var dragTranslationY: CGFloat = 0
    @State private var manualOffset: CGFloat = 0
    @State private var isUserDragging: Bool = false
    @State private var scrollStartTime = Date()
    /// Cached offset used for the static (non-animated) teleprompter snapshot.
    /// Updated whenever scrolling stops or a drag ends while paused.
    @State private var staticOffsetY: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // Only use the 60fps TimelineView when actively auto-scrolling or dragging.
                // When paused, render a static snapshot to save CPU/GPU/battery.
                if isScrolling || isUserDragging {
                    TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                        let totalY = computeOffset(
                            elapsed: context.date.timeIntervalSince(scrollStartTime),
                            viewportHeight: proxy.size.height
                        )
                        ScrollingTeleprompterText(
                            text: config.text,
                            fontSize: config.fontSize,
                            textColor: config.textColor.color,
                            offsetY: totalY
                        )
                    }
                } else {
                    ScrollingTeleprompterText(
                        text: config.text,
                        fontSize: config.fontSize,
                        textColor: config.textColor.color,
                        offsetY: staticOffsetY
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragTranslationY) { value, state, _ in
                        state = value.translation.height
                    }
                    .onChanged { _ in
                        if !isUserDragging {
                            tp("DRAG started manualOffset=\(Int(manualOffset))")
                        }
                        isUserDragging = true
                    }
                    .onEnded { value in
                        let delta = value.translation.height
                        tp("DRAG ended delta=\(Int(delta)) manualOffset \(Int(manualOffset)) -> \(Int(manualOffset + delta))")
                        manualOffset += delta
                        isUserDragging = false
                        // Update static snapshot so the paused branch shows correct position.
                        if !isScrolling {
                            staticOffsetY = computeOffset(elapsed: 0, viewportHeight: viewportHeight)
                        }
                    }
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Theme.overlayScrim.opacity(config.backgroundOpacity))
            .clipped()
            // Fade text at top and bottom edges so script blends in/out smoothly.
            .mask(alignment: .center) {
                VStack(spacing: 0) {
                    // this is not used but keep it for now. RG June 4, 2026.
                    LinearGradient(colors: [.clear, .black],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 48) // taller fade at bottom — text enters here
                }
            }
            // Eyeline indicator — points talent where to focus their gaze.
            // Height matches one line of text (fontSize × 1.4); width is half that.
            .overlay(alignment: .topTrailing) {
                let lineH = CGFloat(config.fontSize) * 1.4
                EyelineTriangle()
                    .fill(Theme.white.opacity(0.55))
                    .frame(width: lineH * 0.5, height: lineH)
                    .padding(.top, 60)
                    .padding(.trailing, Theme.space8)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if kTeleprompterDebugHUD {
                    TimelineView(.animation(minimumInterval: 1 / 10)) { context in
                        TeleprompterDebugHUD(
                            config: config,
                            measuredTextHeight: measuredTextHeight,
                            manualOffset: manualOffset,
                            isScrolling: isScrolling,
                            scrollStartTime: scrollStartTime,
                            viewportH: proxy.size.height,
                            date: context.date
                        )
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                viewportHeight = proxy.size.height
                tp("onAppear viewportH=\(Int(viewportHeight)) textLen=\(config.text.count)")
                remeasureText(width: proxy.size.width)
            }
            // .task(id:) is more reliable than .onChange for large strings & view re-creations.
            .task(id: TextMeasureKey(text: config.text, fontSize: config.fontSize, width: proxy.size.width)) {
                tp("task(id:) fired textLen=\(config.text.count) width=\(Int(proxy.size.width))")
                remeasureText(width: proxy.size.width)
            }
            .onChange(of: proxy.size.height) { _, newValue in
                tp("viewport size change \(Int(viewportHeight)) -> \(Int(newValue))")
                viewportHeight = newValue
                if !isScrolling { resetScrollPosition() }
            }
            .onChange(of: resetToken) { _, _ in
                let geo = TeleprompterGeometry(
                    viewportHeight: viewportHeight,
                    textHeight: max(measuredTextHeight, 1),
                    fontSize: CGFloat(config.fontSize),
                    verticalPadding: Theme.space16
                )
                tp("RESET manualOffset \(Int(manualOffset)) -> 0 | startOffset=\(Int(geo.startOffset)) floor=\(Int(geo.scrollStopOffset)) ceil=\(Int(geo.dragCeiling)) vpH=\(Int(viewportHeight)) textH=\(Int(measuredTextHeight)) lineH=\(Int(geo.lineHeight))")
                manualOffset = 0
                resetScrollPosition()
            }
            .onChange(of: isScrolling) { _, newValue in
                tp("isScrolling -> \(newValue)")
                handleScrollStateChanged(newValue)
            }
        }
    }

    // MARK: - UIKit-based text measurement (reliable replacement for PreferenceKey path)

    private func remeasureText(width: CGFloat) {
        guard let total = measureTeleprompterTextHeight(
            text: config.text, fontSize: config.fontSize, viewWidth: width
        ) else { return }
        if abs(measuredTextHeight - total) > 0.5 {
            tp("MEASURE width=\(Int(width)) textLen=\(config.text.count) -> textH=\(Int(total)) (was \(Int(measuredTextHeight)))")
            measuredTextHeight = total
            onTextHeightChanged(total)
            if !isScrolling { resetScrollPosition() }
        }
    }

    // MARK: - Scroll state

    /// Computes the clamped offset for the teleprompter text position.
    /// Extracted so both the animated TimelineView and static snapshot share the same formula.
    private func computeOffset(elapsed: TimeInterval, viewportHeight: CGFloat) -> CGFloat {
        let geometry = TeleprompterGeometry(
            viewportHeight: viewportHeight,
            textHeight: max(measuredTextHeight, 1),
            fontSize: CGFloat(config.fontSize),
            verticalPadding: Theme.space16
        )
        let baseOffset = geometry.startOffset
        let autoOffset = (isScrolling && !isUserDragging) ? -elapsed * config.speedPointsPerSecond : 0
        let interim = baseOffset + manualOffset + dragTranslationY + autoOffset
        return min(max(interim, geometry.scrollStopOffset), geometry.dragCeiling)
    }

    /// Snapshots the current offset into `staticOffsetY` for the paused branch.
    private func snapshotStaticOffset(viewportHeight: CGFloat) {
        staticOffsetY = computeOffset(elapsed: 0, viewportHeight: viewportHeight)
    }

    private func resetScrollPosition() {
        scrollStartTime = Date()
        staticOffsetY = computeOffset(elapsed: 0, viewportHeight: viewportHeight)
    }

    private func handleScrollStateChanged(_ isNowScrolling: Bool) {
        if isNowScrolling {
            scrollStartTime = Date()
        } else {
            // When stopping, bake the current auto offset into manualOffset so the position sticks
            let elapsed = CGFloat(Date().timeIntervalSince(scrollStartTime))
            let autoApplied = -elapsed * CGFloat(config.speedPointsPerSecond)
            manualOffset += autoApplied
            // Snapshot for the static branch so it renders at the correct position.
            staticOffsetY = computeOffset(elapsed: 0, viewportHeight: viewportHeight)
        }
    }

}

/// Arrow pointing left — indicates the talent's eyeline focus point
/// at the top-right edge of the teleprompter viewport.
private struct EyelineTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))  // top-right
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)) // bottom-right
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY)) // left point (arrow tip)
        p.closeSubpath()
        return p
    }
}
