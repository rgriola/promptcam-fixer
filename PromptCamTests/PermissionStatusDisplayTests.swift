// PermissionStatusDisplayTests.swift
// PromptCamTests
//
// Verifies status label/color mapping for permission states,
// including optional Speech-to-Text authorization statuses.

import AVFoundation
import CoreLocation
import Photos
import Speech
import SwiftUI
import XCTest

@testable import PromptCam

final class PermissionStatusDisplayTests: XCTestCase {

     // MARK: - Camera / Microphone (AVAuthorizationStatus)

     func testAVAuthorizationStatusLabels() {
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: AVAuthorizationStatus.authorized), "Granted")
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: AVAuthorizationStatus.notDetermined), "Not Set")
          XCTAssertEqual(PermissionStatusDisplay.label(for: AVAuthorizationStatus.denied), "Denied")
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: AVAuthorizationStatus.restricted), "Restricted")
     }

     func testAVAuthorizationStatusColors() {
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: AVAuthorizationStatus.authorized), Color.green)
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: AVAuthorizationStatus.notDetermined), Color.orange
          )
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: AVAuthorizationStatus.denied), Color.red)
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: AVAuthorizationStatus.restricted), Color.red)
     }

     // MARK: - Photos (PHAuthorizationStatus)

     func testPhotoAuthorizationStatusLabels() {
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: PHAuthorizationStatus.authorized), "Granted")
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: PHAuthorizationStatus.limited), "Granted")
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: PHAuthorizationStatus.notDetermined), "Not Set")
          XCTAssertEqual(PermissionStatusDisplay.label(for: PHAuthorizationStatus.denied), "Denied")
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: PHAuthorizationStatus.restricted), "Restricted")
     }

     func testPhotoAuthorizationStatusColors() {
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: PHAuthorizationStatus.authorized), Color.green)
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: PHAuthorizationStatus.limited), Color.green)
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: PHAuthorizationStatus.notDetermined), Color.orange
          )
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: PHAuthorizationStatus.denied), Color.red)
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: PHAuthorizationStatus.restricted), Color.red)
     }

     // MARK: - Location (CLAuthorizationStatus)

     func testLocationAuthorizationStatusLabels() {
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: CLAuthorizationStatus.authorizedWhenInUse),
               "Granted")
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: CLAuthorizationStatus.authorizedAlways), "Granted"
          )
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: CLAuthorizationStatus.notDetermined), "Not Set")
          XCTAssertEqual(PermissionStatusDisplay.label(for: CLAuthorizationStatus.denied), "Denied")
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: CLAuthorizationStatus.restricted), "Restricted")
     }

     func testLocationAuthorizationStatusColors() {
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: CLAuthorizationStatus.authorizedWhenInUse),
               Color.green)
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: CLAuthorizationStatus.authorizedAlways),
               Color.green)
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: CLAuthorizationStatus.notDetermined), Color.orange
          )
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: CLAuthorizationStatus.denied), Color.red)
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: CLAuthorizationStatus.restricted), Color.red)
     }

     // MARK: - Speech-to-Text (SFSpeechRecognizerAuthorizationStatus)

     func testSpeechAuthorizationStatusLabels() {
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: SFSpeechRecognizerAuthorizationStatus.authorized),
               "Granted")
          XCTAssertEqual(
               PermissionStatusDisplay.label(
                    for: SFSpeechRecognizerAuthorizationStatus.notDetermined), "Not Set")
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: SFSpeechRecognizerAuthorizationStatus.denied),
               "Denied")
          XCTAssertEqual(
               PermissionStatusDisplay.label(for: SFSpeechRecognizerAuthorizationStatus.restricted),
               "Restricted")
     }

     func testSpeechAuthorizationStatusColors() {
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: SFSpeechRecognizerAuthorizationStatus.authorized),
               Color.green)
          XCTAssertEqual(
               PermissionStatusDisplay.color(
                    for: SFSpeechRecognizerAuthorizationStatus.notDetermined), Color.orange)
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: SFSpeechRecognizerAuthorizationStatus.denied),
               Color.red)
          XCTAssertEqual(
               PermissionStatusDisplay.color(for: SFSpeechRecognizerAuthorizationStatus.restricted),
               Color.red)
     }
}
