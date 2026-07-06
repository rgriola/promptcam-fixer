// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - External display scene delegate
// Bridges UIKit scene lifecycle to ExternalDisplayService.
// Wired via UISceneConfigurations in project.yml (external-display-non-interactive role).

import UIKit

final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Task { @MainActor in
            ExternalDisplayService.shared.attach(to: windowScene)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Task { @MainActor in
            ExternalDisplayService.shared.detach(from: windowScene)
        }
    }
}
