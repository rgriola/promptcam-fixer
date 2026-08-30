// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Temporary warning banner component
import SwiftUI

/// A warning banner that appears at the top center of the screen. Auto-dismisses
/// after `autoDismissAfter`, or stays until dismissed by the caller when `nil`.
struct TemporaryWarningBanner: View {
    let message: String
    let systemImage: String
    let autoDismissAfter: TimeInterval?
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack {
            if isPresented {
                HStack(spacing: Theme.space8) {
                    Image(systemName: systemImage)
                        .font(Theme.font22Semibold)
                    
                    Text(message)
                        .font(Theme.font16Medium)
                }
                .foregroundStyle(Theme.white)
                .padding(.horizontal, Theme.space16)
                .padding(.vertical, Theme.space12)
                .background(
                    Capsule()
                        .fill(Theme.red.opacity(0.9))
                        .shadow(color: Theme.black.opacity(0.3), radius: 8, y: 4)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: isPresented) {
                    guard isPresented, let autoDismissAfter else { return }
                    try? await Task.sleep(for: .seconds(autoDismissAfter))
                    guard !Task.isCancelled else { return }
                    withAnimation(Theme.easeInOut3) {
                        isPresented = false
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.space16)
        .animation(Theme.easeInOut3, value: isPresented)
        .allowsHitTesting(false)
    }
}
