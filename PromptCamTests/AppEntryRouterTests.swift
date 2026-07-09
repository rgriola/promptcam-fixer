// AppEntryRouterTests.swift
// PromptCamTests
//
// Phase 5 tests for launch and lifecycle app-entry routing decisions.

import XCTest

@testable import PromptCam

final class AppEntryRouterTests: XCTestCase {

    func testRoutesToCameraForUITestBypassEvenWhenPermissionsMissing() {
        let route = AppEntryRouter.route(
            hasCompletedOnboarding: false,
            showCamera: false,
            skipOnboardingForUITest: true,
            hasRequiredPermissions: false
        )

        XCTAssertEqual(route, .camera)
    }

    func testRoutesToOnboardingWhenRequiredPermissionsMissingAfterOnboardingComplete() {
        let route = AppEntryRouter.route(
            hasCompletedOnboarding: true,
            showCamera: true,
            skipOnboardingForUITest: false,
            hasRequiredPermissions: false
        )

        XCTAssertEqual(route, .onboarding)
    }

    func testRoutesToCameraWhenOnboardingCompleteAndRequiredPermissionsGranted() {
        let route = AppEntryRouter.route(
            hasCompletedOnboarding: true,
            showCamera: false,
            skipOnboardingForUITest: false,
            hasRequiredPermissions: true
        )

        XCTAssertEqual(route, .camera)
    }

    func testRoutesToOnboardingOnFreshLaunchWithoutRequiredPermissions() {
        let route = AppEntryRouter.route(
            hasCompletedOnboarding: false,
            showCamera: false,
            skipOnboardingForUITest: false,
            hasRequiredPermissions: false
        )

        XCTAssertEqual(route, .onboarding)
    }

    func testRouteStaysOnOnboardingWhenSettingsReturnUnchanged() {
        let initial = AppEntryRouter.route(
            hasCompletedOnboarding: true,
            showCamera: true,
            skipOnboardingForUITest: false,
            hasRequiredPermissions: false
        )
        let afterReturn = AppEntryRouter.route(
            hasCompletedOnboarding: true,
            showCamera: true,
            skipOnboardingForUITest: false,
            hasRequiredPermissions: false
        )

        XCTAssertEqual(initial, .onboarding)
        XCTAssertEqual(afterReturn, .onboarding)
    }
}
