import SwiftUI
import UIKit
import os

/// Diagnostic HUD overlay. Keep off for normal use; flip true while debugging offset math.
private let kTeleprompterDebugHUD = false

private let tpLog = Logger(subsystem: "com.promptcam.fixer", category: "Teleprompter")

@inline(__always)
private func tp(_ msg: @autoclosure () -> String) {
    let m = msg()
    tpLog.debug("\(m, privacy: .public)")
    print("[TP] \(m)")
}

struct TeleprompterOverlayView: View {
    let text: String
    let fontSize: Double
    let speed: Double
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

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                    let elapsed = context.date.timeIntervalSince(scrollStartTime)
                    let geometry = TeleprompterGeometry(
                        viewportHeight: proxy.size.height,
                        textHeight: max(measuredTextHeight, 1),
                        fontSize: CGFloat(fontSize),
                        verticalPadding: Theme.space16
                    )
                    let baseOffset = geometry.startOffset
                    let autoOffset = (isScrolling && !isUserDragging) ? -elapsed * speed : 0
                    let interim = baseOffset + manualOffset + dragTranslationY + autoOffset
                    // Floor: can't scroll past last line exiting top.
                    // Ceiling: can't drag first line below viewportH − lineH.
                    let totalY = min(max(interim, geometry.scrollStopOffset), geometry.dragCeiling)

                    ScrollingTeleprompterText(
                        text: text,
                        fontSize: fontSize,
                        offsetY: totalY
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
                    }
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Theme.overlayScrim.opacity(0.15))
            .clipped()
            .overlay(alignment: .topLeading) {
                if kTeleprompterDebugHUD {
                    TimelineView(.animation(minimumInterval: 1 / 10)) { context in
                        debugHUD(at: context.date, viewportH: proxy.size.height)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                viewportHeight = proxy.size.height
                tp("onAppear viewportH=\(Int(viewportHeight)) textLen=\(text.count)")
                remeasureText(width: proxy.size.width)
            }
            // .task(id:) is more reliable than .onChange for large strings & view re-creations.
            .task(id: TextMeasureKey(text: text, fontSize: fontSize, width: proxy.size.width)) {
                tp("task(id:) fired textLen=\(text.count) width=\(Int(proxy.size.width))")
                remeasureText(width: proxy.size.width)
            }
            .onChange(of: proxy.size.height) { newValue in
                tp("viewport size change \(Int(viewportHeight)) -> \(Int(newValue))")
                viewportHeight = newValue
                if !isScrolling { resetScrollPosition() }
            }
            .onChange(of: resetToken) { _ in
                let geo = TeleprompterGeometry(
                    viewportHeight: viewportHeight,
                    textHeight: max(measuredTextHeight, 1),
                    fontSize: CGFloat(fontSize),
                    verticalPadding: Theme.space16
                )
                tp("RESET manualOffset \(Int(manualOffset)) -> 0 | startOffset=\(Int(geo.startOffset)) floor=\(Int(geo.scrollStopOffset)) ceil=\(Int(geo.dragCeiling)) vpH=\(Int(viewportHeight)) textH=\(Int(measuredTextHeight)) lineH=\(Int(geo.lineHeight))")
                manualOffset = 0
                resetScrollPosition()
            }
            .onChange(of: isScrolling) { newValue in
                tp("isScrolling -> \(newValue)")
                handleScrollStateChanged(newValue)
            }
        }
    }

    private struct ScrollingTeleprompterText: View {
        let text: String
        let fontSize: Double
        let offsetY: CGFloat

        var body: some View {
            GeometryReader { geo in
                Text(text)
                    .font(Theme.fontFamily.rounded(size: fontSize, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.space24)
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

    // MARK: - UIKit-based text measurement (reliable replacement for PreferenceKey path)

    private func remeasureText(width: CGFloat) {
        guard width > 0 else { return }
        let horizontalPadding = Theme.space24 * 2
        let availableWidth = max(width - horizontalPadding, 1)
        let uiFont = UIFont.systemFont(ofSize: CGFloat(fontSize), weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: uiFont]
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let verticalPadding = Theme.space16 * 2
        let total = ceil(bounding.height) + verticalPadding
        if abs(measuredTextHeight - total) > 0.5 {
            tp("MEASURE width=\(Int(width)) availW=\(Int(availableWidth)) textLen=\(text.count) boundH=\(Int(bounding.height)) vPad=\(Int(verticalPadding)) -> textH=\(Int(total)) (was \(Int(measuredTextHeight)))")
            measuredTextHeight = total
            onTextHeightChanged(total)
            if !isScrolling { resetScrollPosition() }
        }
    }

    // MARK: - Scroll state

    private func resetScrollPosition() {
        scrollStartTime = Date()
    }

    private func handleScrollStateChanged(_ isNowScrolling: Bool) {
        if isNowScrolling {
            scrollStartTime = Date()
        } else {
            // When stopping, bake the current auto offset into manualOffset so the position sticks
            let elapsed = CGFloat(Date().timeIntervalSince(scrollStartTime))
            let autoApplied = -elapsed * CGFloat(speed)
            manualOffset += autoApplied
        }
    }

    // MARK: - Debug HUD

    @ViewBuilder
    private func debugHUD(at date: Date, viewportH: CGFloat) -> some View {
        let geo = TeleprompterGeometry(
            viewportHeight: viewportH,
            textHeight: max(measuredTextHeight, 1),
            fontSize: CGFloat(fontSize),
            verticalPadding: Theme.space16
        )
        let elapsed = date.timeIntervalSince(scrollStartTime)
        let autoOff = isScrolling ? -elapsed * speed : 0
        let rendered = min(max(geo.startOffset + manualOffset + autoOff, geo.scrollStopOffset), geo.dragCeiling)
        VStack(alignment: .leading, spacing: 2) {
            Text("TP-DEBUG").foregroundStyle(.red)
            Text("viewportH: \(Int(viewportH))")
            Text("textH:     \(Int(measuredTextHeight))")
            Text("textLen:   \(text.count)")
            Text("offset:    \(Int(rendered))")
            Text("manual:    \(Int(manualOffset))")
            Text("start:     \(Int(geo.startOffset))")
            Text("floor:     \(Int(geo.scrollStopOffset))")
            Text("ceiling:   \(Int(geo.dragCeiling))")
            Text("scrolling: \(isScrolling ? "YES" : "no")")
            Text("speed:     \(Int(speed))")
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

/// Composite key used by `.task(id:)` to trigger re-measurement when the text,
/// font size, or available width changes. Uses text length + a hash so giant
/// strings don't get fully copied on every body eval.
private struct TextMeasureKey: Hashable {
    let length: Int
    let hash: Int
    let fontSize: Double
    let width: CGFloat

    init(text: String, fontSize: Double, width: CGFloat) {
        self.length = text.count
        self.hash = text.hashValue
        self.fontSize = fontSize
        self.width = width
    }
}
