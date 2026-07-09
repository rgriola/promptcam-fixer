// PermissionRecoveryMapperTests.swift
// PromptCamTests
//
// Phase 4 tests for runtime permission recovery mapping.

import AVFoundation
import CoreLocation
import Photos
import Speech
import XCTest

@testable import PromptCam

final class PermissionRecoveryMapperTests: XCTestCase {

     func testRuntimeRecoveryMapsCameraDeniedToOpenSettings() {
          let snapshot = PermissionPolicySnapshot(
               camera: .denied,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let result = PermissionRecoveryMapper.runtimeRecovery(
               for: .sessionNotReady,
               snapshot: snapshot
          )

          XCTAssertEqual(result.action, .openSettings)
          XCTAssertTrue(result.title.contains("Camera"))
     }

     func testRuntimeRecoveryMapsMicrophoneRestrictedToOpenSettings() {
          let snapshot = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .restricted,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let result = PermissionRecoveryMapper.runtimeRecovery(
               for: .recordingFailed("input lost"),
               snapshot: snapshot
          )

          XCTAssertEqual(result.action, .openSettings)
          XCTAssertTrue(result.title.contains("Microphone"))
     }

     func testRuntimeRecoveryMapsPhotoDeniedToOpenSettings() {
          let snapshot = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .denied,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let result = PermissionRecoveryMapper.runtimeRecovery(
               for: .photoLibraryPermissionDenied,
               snapshot: snapshot
          )

          XCTAssertEqual(result.action, .openSettings)
          XCTAssertTrue(result.title.contains("Photo Library"))
     }

     func testRuntimeRecoveryMapsPermissionLikeSaveFailureToOpenSettings() {
          let snapshot = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let result = PermissionRecoveryMapper.runtimeRecovery(
               for: .photoLibrarySaveFailed("permission denied while writing asset"),
               snapshot: snapshot
          )

          XCTAssertEqual(result.action, .openSettings)
          XCTAssertTrue(result.title.contains("Photo Library"))
     }

     func testRuntimeRecoveryKeepsNonPermissionSaveFailureDismissOnly() {
          let snapshot = PermissionPolicySnapshot(
               camera: .authorized,
               microphone: .authorized,
               photoLibrary: .authorized,
               location: .authorizedWhenInUse,
               speechToText: .authorized
          )

          let result = PermissionRecoveryMapper.runtimeRecovery(
               for: .photoLibrarySaveFailed("disk full"),
               snapshot: snapshot
          )

          XCTAssertEqual(result.action, .dismiss)
          XCTAssertTrue(result.title.contains("Save"))
     }

     func testOptionalSpeechRecoveryMessageShownForDeniedOrRestricted() {
          XCTAssertNotNil(PermissionRecoveryMapper.optionalSpeechRecoveryMessage(for: .denied))
          XCTAssertNotNil(PermissionRecoveryMapper.optionalSpeechRecoveryMessage(for: .restricted))
          XCTAssertNil(PermissionRecoveryMapper.optionalSpeechRecoveryMessage(for: .authorized))
     }
}
