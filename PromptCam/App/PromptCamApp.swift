import SwiftUI
import UIKit

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

    init() {
        // One-time launch snapshot for HDMI debugging. Confirms whether iOS
        // saw any external screens before the app finished initializing.
        let screenCount = UIScreen.screens.count
        let sceneCount = UIApplication.shared.connectedScenes.count
        Log.hdmi.info("PromptCamApp.init screens=\(screenCount, privacy: .public) scenes=\(sceneCount, privacy: .public)")
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
