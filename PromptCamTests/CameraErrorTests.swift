// CameraErrorTests.swift
// PromptCamTests
//
// Verifies every CameraError case produces a non-empty localizedDescription.

import XCTest
@testable import PromptCam

final class CameraErrorTests: XCTestCase {

    // MARK: - Session / Device Errors

    func testDeviceUnavailableDescription() {
        let error = CameraError.deviceUnavailable
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "deviceUnavailable should have a non-empty description")
    }

    func testInputConfigurationFailedDescription() {
        let error = CameraError.inputConfigurationFailed
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "inputConfigurationFailed should have a non-empty description")
    }

    func testOutputConfigurationFailedDescription() {
        let error = CameraError.outputConfigurationFailed
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "outputConfigurationFailed should have a non-empty description")
    }

    func testSessionConfigurationFailedDescription() {
        let error = CameraError.sessionConfigurationFailed("test detail")
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "sessionConfigurationFailed should have a non-empty description")
        XCTAssertTrue(error.localizedDescription.contains("test detail"),
                      "sessionConfigurationFailed should include the detail string")
    }

    func testSessionNotReadyDescription() {
        let error = CameraError.sessionNotReady
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "sessionNotReady should have a non-empty description")
    }

    func testSessionRuntimeErrorDescription() {
        let error = CameraError.sessionRuntimeError("media services unavailable")
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "sessionRuntimeError should have a non-empty description")
        XCTAssertTrue(error.localizedDescription.contains("media services unavailable"),
                      "sessionRuntimeError should include the detail string")
    }

    // MARK: - Format Errors

    func testFormatChangeDuringRecordingDescription() {
        let error = CameraError.formatChangeDuringRecording
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "formatChangeDuringRecording should have a non-empty description")
    }

    func testFormatUnavailableDescription() {
        let error = CameraError.formatUnavailable("4K not supported")
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "formatUnavailable should have a non-empty description")
        XCTAssertTrue(error.localizedDescription.contains("4K not supported"),
                      "formatUnavailable should include the detail string")
    }

    func testFrameRateFailedDescription() {
        let error = CameraError.frameRateFailed("60fps unavailable")
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "frameRateFailed should have a non-empty description")
        XCTAssertTrue(error.localizedDescription.contains("60fps unavailable"),
                      "frameRateFailed should include the detail string")
    }

    // MARK: - Recording Errors

    func testRecordingFailedDescription() {
        let error = CameraError.recordingFailed("disk full")
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "recordingFailed should have a non-empty description")
        XCTAssertTrue(error.localizedDescription.contains("disk full"),
                      "recordingFailed should include the detail string")
    }

    // MARK: - Focus / Exposure Errors

    func testFocusExposureFailedDescription() {
        let error = CameraError.focusExposureFailed("lens error")
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "focusExposureFailed should have a non-empty description")
        XCTAssertTrue(error.localizedDescription.contains("lens error"),
                      "focusExposureFailed should include the detail string")
    }

    // MARK: - Photo Library Errors

    func testPhotoLibraryPermissionDeniedDescription() {
        let error = CameraError.photoLibraryPermissionDenied
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "photoLibraryPermissionDenied should have a non-empty description")
    }

    func testPhotoLibrarySaveFailedDescription() {
        let error = CameraError.photoLibrarySaveFailed("write error")
        XCTAssertFalse(error.localizedDescription.isEmpty,
                       "photoLibrarySaveFailed should have a non-empty description")
        XCTAssertTrue(error.localizedDescription.contains("write error"),
                      "photoLibrarySaveFailed should include the detail string")
    }
}
