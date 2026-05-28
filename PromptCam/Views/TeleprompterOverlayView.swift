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
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                }
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: offset)
                .background(Color.black.opacity(0.15))
                .onChange(of: isScrolling) { _, newValue in
                    if newValue {
                        startTime = Date()
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
