import SwiftUI

@main
struct PromptCamApp: App {
    /// Persists whether the user has completed onboarding.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Tracks whether to show the camera view this session.
    @State private var showCamera = false

    /// Stable ViewModel instance — survives body re-evaluation.
    @State private var viewModel = CameraViewModel()

    /// UI-test bypass: launch with `-uitest-skip-onboarding` to land directly on the camera.
    private var skipOnboardingForUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-skip-onboarding")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding || showCamera || skipOnboardingForUITest {
                    CameraView(viewModel: viewModel)
                } else {
                    PermissionsOnboardingView {
                        hasCompletedOnboarding = true
                        showCamera = true
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
