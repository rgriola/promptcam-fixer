// CameraViewModelTests.swift
// PromptCamTests
//
// Unit tests for CameraViewModel using MockCameraService.
// CameraViewModel is @MainActor and uses @Observable (not ObservableObject).

import XCTest
@testable import PromptCam

@MainActor
final class CameraViewModelTests: XCTestCase {

    private var mockService: MockCameraService!
    private var sut: CameraViewModel!

    override func setUp() {
        super.setUp()
        mockService = MockCameraService()
        sut = CameraViewModel(cameraService: mockService)
    }

    override func tearDown() {
        sut = nil
        mockService = nil
        super.tearDown()
    }

    // MARK: - Recording

    func testToggleRecordingStartsWhenReady() {
        // Simulate camera becoming ready via the session running callback
        mockService.onSessionRunningStateChanged?(true)

        sut.toggleRecording()

        XCTAssertTrue(mockService.startRecordingCalled,
                      "startRecording should be called when camera is ready")
        XCTAssertFalse(mockService.stopRecordingCalled,
                       "stopRecording should NOT be called on first toggle")
    }

    func testToggleRecordingDoesNothingWhenNotReady() {
        // isCameraReady defaults to false; do NOT set it
        sut.toggleRecording()

        XCTAssertFalse(mockService.startRecordingCalled,
                       "startRecording should NOT be called when camera is not ready")
        XCTAssertFalse(mockService.stopRecordingCalled,
                       "stopRecording should NOT be called when camera is not ready")
    }

    func testToggleRecordingStopsWhenRecording() {
        // Simulate camera ready + currently recording
        mockService.onSessionRunningStateChanged?(true)
        mockService.onRecordingStateChanged?(true)

        sut.toggleRecording()

        XCTAssertTrue(mockService.stopRecordingCalled,
                      "stopRecording should be called when already recording")
        XCTAssertFalse(mockService.startRecordingCalled,
                       "startRecording should NOT be called when stopping")
    }

    // MARK: - Session Lifecycle

    func testOnAppearConfiguresAndStartsSession() {
        sut.onAppear()

        XCTAssertTrue(mockService.configureSessionCalled,
                      "configureSession should be called on appear")
        XCTAssertTrue(mockService.startSessionCalled,
                      "startSession should be called on appear")
    }

    func testOnDisappearStopsSession() {
        sut.onDisappear()

        XCTAssertTrue(mockService.stopSessionCalled,
                      "stopSession should be called on disappear")
        XCTAssertFalse(sut.isCameraReady,
                       "isCameraReady should be false after disappear")
    }

    // MARK: - Callbacks

    func testOnRecordingStateChangedUpdatesIsRecording() {
        XCTAssertFalse(sut.isRecording, "isRecording should default to false")

        mockService.onRecordingStateChanged?(true)

        XCTAssertTrue(sut.isRecording,
                      "isRecording should be true after callback fires with true")

        mockService.onRecordingStateChanged?(false)

        XCTAssertFalse(sut.isRecording,
                       "isRecording should be false after callback fires with false")
    }

    func testOnSessionRunningStateChangedUpdatesIsCameraReady() {
        XCTAssertFalse(sut.isCameraReady, "isCameraReady should default to false")

        mockService.onSessionRunningStateChanged?(true)

        XCTAssertTrue(sut.isCameraReady,
                      "isCameraReady should be true after callback fires with true")

        mockService.onSessionRunningStateChanged?(false)

        XCTAssertFalse(sut.isCameraReady,
                       "isCameraReady should be false after callback fires with false")
    }

    func testOnErrorUpdatesCameraError() {
        XCTAssertNil(sut.cameraError, "cameraError should default to nil")

        mockService.onError?(.deviceUnavailable)

        XCTAssertNotNil(sut.cameraError,
                        "cameraError should be set after onError fires")
    }

    // MARK: - Format

    func testUpdateRecordingFormatCallsApplyFormat() {
        let format = RecordingFormat(resolution: .uhd4K, frameRate: .fps60, mode: .standard)

        sut.updateRecordingFormat(format)

        XCTAssertEqual(mockService.lastAppliedFormat, format,
                       "applyFormat should be called with the given format")
    }

    func testUpdateRecordingFormatNoOpWhileRecording() {
        // Simulate recording state
        mockService.onRecordingStateChanged?(true)

        let format = RecordingFormat(resolution: .uhd4K, frameRate: .fps60, mode: .standard)
        sut.updateRecordingFormat(format)

        XCTAssertNil(mockService.lastAppliedFormat,
                     "applyFormat should NOT be called while recording")
    }

    // MARK: - Sheet Routing

    func testOpenPhotoLibrarySetsActiveSheet() {
        sut.openPhotoLibrary()

        XCTAssertEqual(sut.modalQueue.activeSheet, .recordingsLibrary,
                       "activeSheet should be .recordingsLibrary after openPhotoLibrary")
    }

    func testOpenComposeSetsActiveSheet() {
        sut.openCompose()

        XCTAssertTrue(sut.showComposeSheet,
                      "showComposeSheet should be true after openCompose")
        XCTAssertEqual(sut.cameraMode, .compose,
                       "cameraMode should be .compose after openCompose")
    }

    func testOpenFormatPanelBlockedWhileRecording() {
        // Simulate recording state
        mockService.onRecordingStateChanged?(true)

        sut.openFormatPanel()

        XCTAssertNil(sut.modalQueue.activeSheet,
                     "activeSheet should remain nil when recording blocks format panel")
        XCTAssertTrue(sut.showFormatLockedWarning,
                      "showFormatLockedWarning should be true when format panel is blocked")
    }

    // MARK: - Lock Status

    func testUnlockFocusExposureResetsLockStatus() {
        // First, simulate a lock
        sut.lockFocusExposure(at: CGPoint(x: 0.5, y: 0.5))
        // Simulate the service completing with afAeLocked
        mockService.lastLockCompletion?(.afAeLocked)
        XCTAssertEqual(sut.lockStatus, .aeAfLocked,
                       "lockStatus should be aeAfLocked after lock callback")

        // Now unlock
        sut.unlockFocusExposure()

        XCTAssertEqual(sut.lockStatus, .auto,
                       "lockStatus should be .auto after unlockFocusExposure")
        XCTAssertTrue(mockService.unlockFocusExposureCalled,
                      "unlockFocusExposure should be called on the service")
    }

    // MARK: - Teleprompter

    func testToggleScrollingTogglesState() {
        XCTAssertFalse(sut.isScrolling, "isScrolling should default to false")

        sut.toggleScrolling()

        XCTAssertTrue(sut.isScrolling,
                      "isScrolling should be true after first toggle")

        sut.toggleScrolling()

        XCTAssertFalse(sut.isScrolling,
                       "isScrolling should be false after second toggle")
    }

    func testResetTeleprompterPositionIncrementsToken() {
        let initialToken = sut.teleprompterResetToken

        sut.resetTeleprompterPosition()

        XCTAssertGreaterThan(sut.teleprompterResetToken, initialToken,
                             "teleprompterResetToken should increase after reset")
    }

    // MARK: - Script Persistence

    func testUpdateScriptText_persistsToUserDefaults() {
        let scriptKey = "tp.scriptText"
        UserDefaults.standard.removeObject(forKey: scriptKey)
        defer { UserDefaults.standard.removeObject(forKey: scriptKey) }

        sut.updateScriptText("My reporter script.")

        let saved = UserDefaults.standard.string(forKey: scriptKey)
        XCTAssertEqual(saved, "My reporter script.",
                       "updateScriptText must persist the script to UserDefaults")
    }

    func testUpdateScriptText_doesNotSaveDefaultPlaceholder() {
        let scriptKey = "tp.scriptText"
        UserDefaults.standard.removeObject(forKey: scriptKey)
        defer { UserDefaults.standard.removeObject(forKey: scriptKey) }

        // Saving the default hint text should NOT persist it — ensures a
        // fresh install still shows the hint on next launch.
        sut.updateScriptText(TeleprompterConfig.default.text)

        let saved = UserDefaults.standard.string(forKey: scriptKey)
        XCTAssertNil(saved,
                     "Default placeholder text must not be written to UserDefaults")
    }

    func testNewViewModel_restoresSavedScript() {
        let scriptKey = "tp.scriptText"
        UserDefaults.standard.removeObject(forKey: scriptKey)
        defer { UserDefaults.standard.removeObject(forKey: scriptKey) }

        // Simulate saving a script in one session.
        sut.updateScriptText("Breaking news script.")

        // Create a new ViewModel — simulates a cold app relaunch.
        let relaunchedVM = CameraViewModel(cameraService: MockCameraService())

        XCTAssertEqual(relaunchedVM.config.text, "Breaking news script.",
                       "Script must be restored from UserDefaults after relaunch")
    }

    func testNewViewModel_showsDefaultTextWhenNoScriptSaved() {
        let scriptKey = "tp.scriptText"
        UserDefaults.standard.removeObject(forKey: scriptKey)
        defer { UserDefaults.standard.removeObject(forKey: scriptKey) }

        let freshVM = CameraViewModel(cameraService: MockCameraService())

        XCTAssertEqual(freshVM.config.text, TeleprompterConfig.default.text,
                       "Fresh install must show the default hint text")
    }
}
