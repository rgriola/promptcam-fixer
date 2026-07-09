// PermissionPolicySnapshotTests.swift
// PromptCamTests
//
// Phase 1 policy tests for required vs optional permission behavior.
// Core flow requires Camera + Microphone + Photo Library.
// Location and Speech-to-Text remain optional.

import AVFoundation
import CoreLocation
import Photos
import Speech
import XCTest

@testable import PromptCam

final class PermissionPolicySnapshotTests: XCTestCase {

     func testRequiredPermissionsGrantedWhenCameraMicAndPhotoAreAuthorized() {
          let snapshot = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .denied,
               speechToText: .denied
          )

          XCTAssertTrue(snapshot.requiredPermissionsGranted)
          XCTAssertFalse(snapshot.shouldBlockAppEntry)
     }

     func testRequiredPermissionsGrantedWhenPhotoLibraryIsLimited() {
          let snapshot = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .limited,
               location: .notDetermined,
               speechToText: .notDetermined
          )

          XCTAssertTrue(snapshot.requiredPermissionsGranted)
          XCTAssertFalse(snapshot.shouldBlockAppEntry)
     }

     func testShouldBlockAppEntryWhenCameraDenied() {
          let snapshot = PermissionPolicySnapshot(
               camera: .denied,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          XCTAssertFalse(snapshot.requiredPermissionsGranted)
          XCTAssertTrue(snapshot.shouldBlockAppEntry)
     }

     func testShouldBlockAppEntryWhenMicrophoneDenied() {
          let snapshot = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .denied,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          XCTAssertFalse(snapshot.requiredPermissionsGranted)
          XCTAssertTrue(snapshot.shouldBlockAppEntry)
     }

     func testShouldBlockAppEntryWhenPhotoLibraryDenied() {
          let snapshot = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .denied,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          XCTAssertFalse(snapshot.requiredPermissionsGranted)
          XCTAssertTrue(snapshot.shouldBlockAppEntry)
     }

     func testSpeechToTextIsOptionalForCoreFlow() {
          let snapshot = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .denied
          )

          XCTAssertTrue(snapshot.requiredPermissionsGranted)
          XCTAssertFalse(snapshot.shouldBlockAppEntry)
          XCTAssertFalse(snapshot.isSpeechToTextAvailable)
     }

     func testOptionalPermissionsGrantedOnlyWhenLocationAndSpeechGranted() {
          let allOptional = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedAlways,
               speechToText: .authorized
          )
          XCTAssertTrue(allOptional.optionalPermissionsGranted)

          let speechDenied = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedAlways,
               speechToText: .denied
          )
          XCTAssertFalse(speechDenied.optionalPermissionsGranted)
     }
}
