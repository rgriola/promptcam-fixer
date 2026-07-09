// PermissionAnalyticsPayloadBuilderTests.swift
// PromptCamTests
//
// Phase 7 payload builder tests for initial analytics events.

import AVFoundation
import CoreLocation
import Photos
import Speech
import XCTest

@testable import PromptCam

final class PermissionAnalyticsPayloadBuilderTests: XCTestCase {

    func testGateShownPayloadIncludesEventAndBlockedPermissions() {
        let snapshot = PermissionPolicySnapshot(
            camera: .denied,
            microphone: .authorized,
            photoLibrary: .notDetermined,
            location: .authorizedWhenInUse,
            speechToText: .authorized
        )

        let payload = PermissionAnalyticsPayloadBuilder.gateShown(
            snapshot: snapshot,
            sourceScreen: "onboarding"
        )

        XCTAssertEqual(payload.event, .permissionGateShown)
        XCTAssertEqual(payload.fields["sourceScreen"], "onboarding")
        XCTAssertEqual(payload.fields["blockedPermissions"], "camera,photoLibrary")
    }

    func testOpenSettingsPayloadIncludesPermissionAndSurface() {
        let snapshot = PermissionPolicySnapshot(
            camera: .authorized,
            microphone: .denied,
            photoLibrary: .authorized,
            location: .notDetermined,
            speechToText: .denied
        )

        let payload = PermissionAnalyticsPayloadBuilder.openSettingsTapped(
            permission: .microphone,
            sourceSurface: .runtimeAlert,
            snapshot: snapshot
        )

        XCTAssertEqual(payload.event, .permissionOpenSettingsTapped)
        XCTAssertEqual(payload.fields["permissionType"], "microphone")
        XCTAssertEqual(payload.fields["sourceSurface"], "runtimeAlert")
        XCTAssertEqual(payload.fields["blockedPermissions"], "microphone")
    }

    func testOpenSettingsPayloadOmitsBlockedPermissionsWithoutSnapshot() {
        let payload = PermissionAnalyticsPayloadBuilder.openSettingsTapped(
            permission: .camera,
            sourceSurface: .settings,
            snapshot: nil
        )

        XCTAssertEqual(payload.event, .permissionOpenSettingsTapped)
        XCTAssertEqual(payload.fields["permissionType"], "camera")
        XCTAssertEqual(payload.fields["sourceSurface"], "settings")
        XCTAssertNil(payload.fields["blockedPermissions"])
    }

    func testGrantAccessPayloadIncludesUndeterminedPermissions() {
        let snapshot = PermissionPolicySnapshot(
            camera: .notDetermined,
            microphone: .notDetermined,
            photoLibrary: .authorized,
            location: .notDetermined,
            speechToText: .authorized
        )

        let payload = PermissionAnalyticsPayloadBuilder.grantAccessTapped(
            snapshot: snapshot,
            sourceScreen: "onboarding"
        )

        XCTAssertEqual(payload.event, .permissionGrantAccessTapped)
        XCTAssertEqual(payload.fields["sourceScreen"], "onboarding")
        XCTAssertEqual(payload.fields["undeterminedPermissions"], "camera,microphone,location")
    }
}
