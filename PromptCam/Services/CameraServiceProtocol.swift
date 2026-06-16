// CameraServiceProtocol.swift
// PromptCam
//
// Protocol for dependency injection — enables unit testing the ViewModel
// without a real AVCaptureSession.

import AVFoundation

/// Defines the public API surface of the camera service layer.
///
/// `CameraViewModel` depends on this protocol rather than the concrete
/// `CameraService` class, which allows injecting a mock for tests.
protocol CameraServiceProtocol: AnyObject, Sendable {

    // MARK: - Preview

    /// The capture session used by the preview layer.
    var previewSession: AVCaptureSession { get }

    // MARK: - Audio

    /// The audio capture device, if available. Used for gain control.
    var audioDevice: AVCaptureDevice? { get }

    // MARK: - Callbacks (set by the ViewModel in bindCallbacks)

    var onRecordingStateChanged: (@MainActor @Sendable (Bool) -> Void)? { get set }
    var onSessionRunningStateChanged: (@MainActor @Sendable (Bool) -> Void)? { get set }
    var onFormatApplied: (@MainActor @Sendable (RecordingFormat) -> Void)? { get set }
    var onSupportedFormatsQueried: (@MainActor @Sendable ([VideoResolution], [VideoFrameRate]) -> Void)? { get set }
    var onDeviceCapabilitiesQueried: (@MainActor @Sendable (DeviceCapabilities) -> Void)? { get set }
    var onCinematicApertureAvailable: (@MainActor @Sendable (Float, Float, Float) -> Void)? { get set }
    var onError: (@MainActor @Sendable (CameraError) -> Void)? { get set }

    // MARK: - Session Lifecycle

    func configureSession(format: RecordingFormat)
    func startSession()
    func stopSession()

    // MARK: - Recording

    func startRecording()
    func stopRecording()

    // MARK: - Format & Cinematic

    func applyFormat(_ format: RecordingFormat)
    func setSimulatedAperture(_ value: Float)

    // MARK: - Focus, Exposure & Lock

    func focus(at devicePoint: CGPoint)
    func lockFocusExposure(at devicePoint: CGPoint)
    func lockFocusExposure(at devicePoint: CGPoint, completion: (@MainActor @Sendable (FocusExposureLockOutcome) -> Void)?)
    func unlockFocusExposure()
    func adjustExposure(by delta: Float)
    func setExposure(to value: Float)
}
