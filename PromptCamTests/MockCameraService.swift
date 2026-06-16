// MockCameraService.swift
// PromptCamTests
//
// Mock implementation of CameraServiceProtocol for unit testing.
// Tracks method calls and stores callback closures for triggering in tests.

import AVFoundation
@testable import PromptCam

final class MockCameraService: CameraServiceProtocol, @unchecked Sendable {

    // MARK: - Preview Session

    let previewSession = AVCaptureSession()
    let audioDevice: AVCaptureDevice? = nil

    // MARK: - Call Tracking

    var configureSessionCalled = false
    var startSessionCalled = false
    var stopSessionCalled = false
    var startRecordingCalled = false
    var stopRecordingCalled = false
    var unlockFocusExposureCalled = false
    var lastAppliedFormat: RecordingFormat?
    var lastConfiguredFormat: RecordingFormat?
    var lastFocusPoint: CGPoint?
    var lastLockPoint: CGPoint?
    var lastApertureValue: Float?
    var lastExposureDelta: Float?
    var lastExposureValue: Float?
    var lastLockCompletion: ((@MainActor @Sendable (FocusExposureLockOutcome) -> Void))?

    // MARK: - Callbacks

    var onRecordingStateChanged: (@MainActor @Sendable (Bool) -> Void)?
    var onSessionRunningStateChanged: (@MainActor @Sendable (Bool) -> Void)?
    var onFormatApplied: (@MainActor @Sendable (RecordingFormat) -> Void)?
    var onSupportedFormatsQueried: (@MainActor @Sendable ([VideoResolution], [VideoFrameRate]) -> Void)?
    var onDeviceCapabilitiesQueried: (@MainActor @Sendable (DeviceCapabilities) -> Void)?
    var onCinematicApertureAvailable: (@MainActor @Sendable (Float, Float, Float) -> Void)?
    var onError: (@MainActor @Sendable (CameraError) -> Void)?

    // MARK: - Session Lifecycle

    func configureSession(format: RecordingFormat) {
        configureSessionCalled = true
        lastConfiguredFormat = format
    }

    func startSession() {
        startSessionCalled = true
    }

    func stopSession() {
        stopSessionCalled = true
    }

    // MARK: - Recording

    func startRecording() {
        startRecordingCalled = true
    }

    func stopRecording() {
        stopRecordingCalled = true
    }

    // MARK: - Format & Cinematic

    func applyFormat(_ format: RecordingFormat) {
        lastAppliedFormat = format
    }

    func setSimulatedAperture(_ value: Float) {
        lastApertureValue = value
    }

    // MARK: - Focus, Exposure & Lock

    func focus(at devicePoint: CGPoint) {
        lastFocusPoint = devicePoint
    }

    func lockFocusExposure(at devicePoint: CGPoint) {
        lastLockPoint = devicePoint
    }

    func lockFocusExposure(at devicePoint: CGPoint, completion: (@MainActor @Sendable (FocusExposureLockOutcome) -> Void)?) {
        lastLockPoint = devicePoint
        lastLockCompletion = completion
    }

    func unlockFocusExposure() {
        unlockFocusExposureCalled = true
    }

    func adjustExposure(by delta: Float) {
        lastExposureDelta = delta
    }

    func setExposure(to value: Float) {
        lastExposureValue = value
    }
}
