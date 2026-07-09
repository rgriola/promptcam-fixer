// RequiredAccessGateStateTests.swift
// PromptCamTests
//
// Phase 3 tests for required-access gate reducer logic.

import AVFoundation
import CoreLocation
import Photos
import Speech
import XCTest

@testable import PromptCam

final class RequiredAccessGateStateTests: XCTestCase {

     func testCanContinueWhenAllRequiredPermissionsGranted() {
          let state = RequiredAccessGateState(
               snapshot: PermissionPolicySnapshot(
                    camera: .authorized,
                    microphone: .authorized,
                    photoLibrary: .authorized,
                    location: .denied,
                    speechToText: .denied
               ))

          XCTAssertTrue(state.canContinue)
     }

     func testCannotContinueWhenPhotoLibraryDenied() {
          let state = RequiredAccessGateState(
               snapshot: PermissionPolicySnapshot(
                    camera: .authorized,
                    microphone: .authorized,
                    photoLibrary: .denied,
                    location: .authorizedWhenInUse,
                    speechToText: .authorized
               ))

          XCTAssertFalse(state.canContinue)
          XCTAssertTrue(state.hasBlockedRequiredPermission)
     }

     func testHasBlockedRequiredPermissionWhenCameraRestricted() {
          let state = RequiredAccessGateState(
               snapshot: PermissionPolicySnapshot(
                    camera: .restricted,
                    microphone: .authorized,
                    photoLibrary: .authorized,
                    location: .authorizedWhenInUse,
                    speechToText: .authorized
               ))

          XCTAssertTrue(state.hasBlockedRequiredPermission)
     }

     func testHasUndeterminedPermissionWhenOptionalSpeechNotDetermined() {
          let state = RequiredAccessGateState(
               snapshot: PermissionPolicySnapshot(
                    camera: .authorized,
                    microphone: .authorized,
                    photoLibrary: .authorized,
                    location: .authorizedWhenInUse,
                    speechToText: .notDetermined
               ))

          XCTAssertTrue(state.canContinue)
          XCTAssertTrue(state.hasUndeterminedPermission)
     }

     func testNoBlockedAndNoUndeterminedWhenEverythingDecidedAndGranted() {
          let state = RequiredAccessGateState(
               snapshot: PermissionPolicySnapshot(
                    camera: .authorized,
                    microphone: .authorized,
                    photoLibrary: .limited,
                    location: .authorizedAlways,
                    speechToText: .authorized
               ))

          XCTAssertTrue(state.canContinue)
          XCTAssertFalse(state.hasBlockedRequiredPermission)
          XCTAssertFalse(state.hasUndeterminedPermission)
     }
}
