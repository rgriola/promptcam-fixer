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

     func testSettingsReturnedPayloadIncludesDiffAndDuration() {
          let previous = PermissionPolicySnapshot(
               camera: .denied,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .denied
          )

          let current = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let payload = PermissionAnalyticsPayloadBuilder.settingsReturned(
               previousSnapshot: previous,
               currentSnapshot: current,
               timeInSettingsMs: 1200
          )

          XCTAssertEqual(payload.event, .permissionSettingsReturned)
          XCTAssertEqual(payload.fields["timeInSettingsMs"], "1200")
          XCTAssertEqual(
               payload.fields["changedPermissions"],
               "camera:denied->authorized,speechToText:denied->authorized")
          XCTAssertEqual(payload.fields["unchangedPermissions"], "microphone,photoLibrary,location")
     }

     func testRecoverySuccessPayloadIncludesRecoveredPermissionsAndSurface() {
          let previous = PermissionPolicySnapshot(
               camera: .denied,
               microphone: .restricted,
               photoLibrary: .denied,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let current = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .limited,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let payload = PermissionAnalyticsPayloadBuilder.recoverySuccess(
               previousSnapshot: previous,
               currentSnapshot: current,
               recoverySurface: .gate,
               recoveryDurationMs: 3000
          )

          XCTAssertEqual(payload.event, .permissionRecoverySuccess)
          XCTAssertEqual(payload.fields["recoveredPermissions"], "camera,microphone,photoLibrary")
          XCTAssertEqual(payload.fields["recoverySurface"], "gate")
          XCTAssertEqual(payload.fields["recoveryDurationMs"], "3000")
     }

     func testBlockedLoopPayloadIncludesLoopCountAndBlockedPermissions() {
          let snapshot = PermissionPolicySnapshot(
               camera: .denied,
               microphone: .authorized,
               photoLibrary: .restricted,
               location: .notDetermined,
               speechToText: .notDetermined
          )

          let payload = PermissionAnalyticsPayloadBuilder.blockedLoopDetected(
               loopCount: 2,
               snapshot: snapshot,
               lastAction: "gateShown"
          )

          XCTAssertEqual(payload.event, .permissionBlockedLoopDetected)
          XCTAssertEqual(payload.fields["loopCount"], "2")
          XCTAssertEqual(payload.fields["blockedPermissions"], "camera,photoLibrary")
          XCTAssertEqual(payload.fields["lastAction"], "gateShown")
     }

     func testSpeechStatusPayloadIncludesSourceAndStatus() {
          let payload = PermissionAnalyticsPayloadBuilder.speechPermissionStatusObserved(
               status: .restricted,
               sourceScreen: "settings"
          )

          XCTAssertEqual(payload.event, .speechPermissionStatusObserved)
          XCTAssertEqual(payload.fields["speechStatus"], "restricted")
          XCTAssertEqual(payload.fields["sourceScreen"], "settings")
     }

     func testSpeechOpenSettingsPayloadIncludesSurfaceAndStatus() {
          let payload = PermissionAnalyticsPayloadBuilder.speechPermissionOpenSettingsTapped(
               sourceSurface: .settings,
               speechStatus: .denied
          )

          XCTAssertEqual(payload.event, .speechPermissionOpenSettingsTapped)
          XCTAssertEqual(payload.fields["sourceSurface"], "settings")
          XCTAssertEqual(payload.fields["speechStatus"], "denied")
     }

     func testSupportDiagnosticSummaryPayloadIncludesRequiredFlag() {
          let snapshot = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .notDetermined
          )

          let payload = PermissionAnalyticsPayloadBuilder.supportDiagnosticSummary(
               snapshot: snapshot,
               sourceScreen: "settings"
          )

          XCTAssertEqual(payload.event, .permissionSupportDiagnosticSummary)
          XCTAssertEqual(payload.fields["sourceScreen"], "settings")
          XCTAssertEqual(payload.fields["requiredPermissionsGranted"], "true")
          XCTAssertEqual(payload.fields["speechToText"], "notDetermined")
     }

     func testSettingsReturnedPayloadWithoutPreviousReportsBaseline() {
          let current = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let payload = PermissionAnalyticsPayloadBuilder.settingsReturned(
               previousSnapshot: nil,
               currentSnapshot: current,
               timeInSettingsMs: nil
          )

          XCTAssertEqual(payload.event, .permissionSettingsReturned)
          XCTAssertNil(payload.fields["timeInSettingsMs"])
          XCTAssertEqual(
               payload.fields["changedPermissions"],
               "camera,microphone,photoLibrary,location,speechToText")
          XCTAssertEqual(payload.fields["unchangedPermissions"], "")
     }

     func testRecoverySuccessPayloadIsEmptyWhenNothingRecovered() {
          let previous = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let current = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let payload = PermissionAnalyticsPayloadBuilder.recoverySuccess(
               previousSnapshot: previous,
               currentSnapshot: current,
               recoverySurface: .runtimeAlert,
               recoveryDurationMs: 500
          )

          XCTAssertEqual(payload.event, .permissionRecoverySuccess)
          XCTAssertEqual(payload.fields["recoveredPermissions"], "")
          XCTAssertEqual(payload.fields["recoverySurface"], "runtimeAlert")
     }
}
