// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Temporary warning banner component
import SwiftUI

/// A temporary warning banner that appears at the top center of the screen
/// and auto-dismisses after a specified duration.
struct TemporaryWarningBanner: View {
    let message: String
    let systemImage: String
    let autoDismissAfter: TimeInterval
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack {
            if isPresented {
                HStack(spacing: Theme.space8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text(message)
                        .font(Theme.font12Medium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.space16)
                .padding(.vertical, Theme.space12)
                .background(
                    Capsule()
                        .fill(.red.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: isPresented) {
                    guard isPresented else { return }
                    try? await Task.sleep(for: .seconds(autoDismissAfter))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPresented = false
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.space16)
        .allowsHitTesting(false)
    }
}
