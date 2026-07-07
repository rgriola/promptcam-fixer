// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - External display scene delegate
// Bridges UIKit scene lifecycle to ExternalDisplayService.
// Wired via UISceneConfigurations in Info.plist (external-display-non-interactive role).

import UIKit

@MainActor
final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    nonisolated func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        MainActor.assumeIsolated {
            Log.hdmi.info("ExternalSceneDelegate.willConnect role=\(String(describing: session.role), privacy: .public) sceneClass=\(String(describing: type(of: scene)), privacy: .public)")
            guard let windowScene = scene as? UIWindowScene else {
                Log.hdmi.error("ExternalSceneDelegate: scene is not UIWindowScene — ignoring")
                return
            }
            // Attach synchronously — deferring via Task lets iOS advance the
            // scene state before the window is installed, which on iPhone can
            // lock the external display into mirror mode.
            ExternalDisplayService.shared.attach(to: windowScene)
        }
    }

    nonisolated func sceneDidDisconnect(_ scene: UIScene) {
        MainActor.assumeIsolated {
            Log.hdmi.info("ExternalSceneDelegate.sceneDidDisconnect")
            guard let windowScene = scene as? UIWindowScene else { return }
            ExternalDisplayService.shared.detach(from: windowScene)
        }
    }

    nonisolated func sceneDidBecomeActive(_ scene: UIScene) {
        MainActor.assumeIsolated {
            Log.hdmi.info("ExternalSceneDelegate.sceneDidBecomeActive activationState=\(String(describing: scene.activationState), privacy: .public)")
        }
    }
}
