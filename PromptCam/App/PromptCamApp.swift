import SwiftUI

@main
struct PromptCamApp: App {
    /// Persists whether the user has completed onboarding.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Tracks whether to show the camera view this session.
    @State private var showCamera = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding || showCamera {
                CameraView(viewModel: CameraViewModel())
            } else {
                PermissionsOnboardingView {
                    hasCompletedOnboarding = true
                    showCamera = true
                }
            }
        }
    }
}
