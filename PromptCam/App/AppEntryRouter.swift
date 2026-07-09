enum AppEntryRoute: Equatable, Sendable {
    case camera
    case onboarding
}

enum AppEntryRouter {
    /// Centralized app-entry routing decision.
    /// Required permissions gate camera entry even after onboarding is complete.
    static func route(
        hasCompletedOnboarding: Bool,
        showCamera: Bool,
        skipOnboardingForUITest: Bool,
        hasRequiredPermissions: Bool
    ) -> AppEntryRoute {
        if skipOnboardingForUITest {
            return .camera
        }

        if (hasCompletedOnboarding || showCamera) && hasRequiredPermissions {
            return .camera
        }

        return .onboarding
    }
}