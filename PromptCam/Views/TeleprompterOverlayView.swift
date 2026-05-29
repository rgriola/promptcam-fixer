// May 29, 2026 - 12:57pm - GitHub Copilot
import SwiftUI

struct TeleprompterOverlayView: View {
    let text: String
    let fontSize: Double
    let speed: Double
    let isScrolling: Bool

    @State private var startTime = Date()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                let elapsed = context.date.timeIntervalSince(startTime)
                let offset = isScrolling ? -elapsed * speed : 0

                ScrollView(showsIndicators: false) {
                    Text(text)
                        .font(Theme.fontFamily.rounded(size: fontSize, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.space24)
                        .padding(.vertical, Theme.space16)
                        .frame(maxWidth: .infinity)
                }
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: offset)
                .background(Theme.overlayScrim.opacity(0.15))
                .onChange(of: isScrolling) { newValue in
                    if newValue {
                        startTime = Date()
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

