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
        // One-time launch snapshot for HDMI debugging. Scene enumeration
        // (openSessions) works even before the first scene connects — it lists
        // sessions the OS has restored from a previous launch. External screen
        // presence is reported via ExternalSceneDelegate when a scene attaches.
        let sceneCount = UIApplication.shared.connectedScenes.count
        let sessionCount = UIApplication.shared.openSessions.count
        Log.hdmi.info("PromptCamApp.init connectedScenes=\(sceneCount, privacy: .public) openSessions=\(sessionCount, privacy: .public)")

        configureUIAppearance()
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

    private func configureUIAppearance() {
        // Set slider thumb appearance globally — runs once on app launch
        let thumbImage = UIImage(
                            systemName: "circle.fill")?
                                .withTintColor(UIColor(Theme.white))
        
        UISlider.appearance()
            .setThumbImage(thumbImage, for: .normal)

        // You can also style the track if needed
        UISlider.appearance().minimumTrackTintColor = UIColor(Theme.accent)
        UISlider.appearance().maximumTrackTintColor = UIColor(Theme.accent.opacity(0.2))
    }
}
