// May 31, 2026 - 12:45am - GitHub Copilot (Claude Opus 4.7)
import SwiftUI

struct TeleprompterOverlayView: View {
    let text: String
    let fontSize: Double
    let speed: Double
    let isScrolling: Bool
    let startOffsetProgress: Double
    let onTextHeightChanged: (CGFloat) -> Void

    @State private var measuredTextHeight: CGFloat = 0
    @State private var pausedOffset: CGFloat = 0
    @State private var scrollStartTime = Date()
    @State private var scrollStartOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                let viewportHeight = proxy.size.height
                let textHeight = max(measuredTextHeight, 1)
                // Auto-scroll floor: last line visible at viewport top (matches progress = 0).
                let minimumOffset = offsetForProgress(0, viewportHeight: viewportHeight, textHeight: textHeight)
                let currentOffset = scrollOffset(at: context.date, minimumOffset: minimumOffset)

                Text(text)
                    .font(Theme.fontFamily.rounded(size: fontSize, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.space24)
                    .padding(.vertical, Theme.space16)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: currentOffset)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: TeleprompterTextHeightPreferenceKey.self,
                                value: geometry.size.height
                            )
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Theme.overlayScrim.opacity(0.15))
                    .clipped()
                    .allowsHitTesting(false)
                    .onChange(of: text) { _ in
                        // New script: invalidate the cached height so the preference path
                        // re-fires and resets against the new content's actual height.
                        measuredTextHeight = 0
                    }
                    .onChange(of: startOffsetProgress) { _ in
                        guard !isScrolling else { return }
                        resetScrollPosition(viewportHeight: viewportHeight, textHeight: textHeight)
                    }
                    .onChange(of: isScrolling) { newValue in
                        handleScrollStateChanged(newValue, minimumOffset: minimumOffset)
                    }
                    .onPreferenceChange(TeleprompterTextHeightPreferenceKey.self) { newHeight in
                        guard newHeight > 0 else { return }
                        let roundedHeight = round(newHeight)
                        if measuredTextHeight != roundedHeight {
                            measuredTextHeight = roundedHeight
                            onTextHeightChanged(roundedHeight)
                        }
                        // Always realign when paused — a new script may measure to the
                        // same rounded height as the previous one.
                        if !isScrolling {
                            resetScrollPosition(viewportHeight: viewportHeight, textHeight: roundedHeight)
                        }
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private func offsetForProgress(_ progress: Double, viewportHeight: CGFloat, textHeight: CGFloat) -> CGFloat {
        // Slider progress maps to reading position. The text block has Theme.space16 of vertical padding.
        //   progress = 1 (knob TOP)    → first line's TOP edge at viewport BOTTOM (script fully below).
        //   progress = 0 (knob BOTTOM) → last line's BOTTOM edge at viewport TOP (script fully above).
        // Traversal = viewportHeight + textHeight - 2 * verticalPadding (scales with textHeight).
        let clampedProgress = CGFloat(min(max(progress, 0), 1))
        let verticalPadding = Theme.space16
        let startOffset = viewportHeight - verticalPadding         // progress = 1
        let endOffset = -(textHeight - verticalPadding)            // progress = 0
        return startOffset + (endOffset - startOffset) * (1 - clampedProgress)
    }

    private func scrollOffset(at date: Date, minimumOffset: CGFloat) -> CGFloat {
        guard isScrolling else { return pausedOffset }
        let elapsed = CGFloat(date.timeIntervalSince(scrollStartTime))
        return max(minimumOffset, scrollStartOffset - elapsed * CGFloat(speed))
    }

    private func resetScrollPosition(viewportHeight: CGFloat, textHeight: CGFloat) {
        let startOffset = offsetForProgress(startOffsetProgress, viewportHeight: viewportHeight, textHeight: max(textHeight, 1))
        pausedOffset = startOffset
        scrollStartOffset = startOffset
        scrollStartTime = Date()
    }

    private func handleScrollStateChanged(_ isNowScrolling: Bool, minimumOffset: CGFloat) {
        if isNowScrolling {
            scrollStartTime = Date()
            scrollStartOffset = pausedOffset
        } else {
            let elapsed = CGFloat(Date().timeIntervalSince(scrollStartTime))
            pausedOffset = max(minimumOffset, scrollStartOffset - elapsed * CGFloat(speed))
        }
    }
}

private struct TeleprompterTextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

