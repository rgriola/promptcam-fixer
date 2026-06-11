// May 30, 2026 - 4:23pm - GitHub Copilot
// June 8, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add setExposure(to:) for reliable absolute reset
import AVFoundation
import Photos

enum FocusExposureLockOutcome: Equatable {
    case afAeLocked
    case aeLocked
    case afLocked
    case unsupported
}

enum PreferredCameraSelection: Equatable {
    case front
    case back
    case unavailable
}

/// Manages the AVCaptureSession lifecycle, recording, and focus/exposure hardware.
///
/// **Threading model**: All camera configuration runs on `sessionQueue` (a serial
/// dispatch queue) to avoid blocking the main thread. Results are relayed back to
/// the main thread via callback closures (`onRecordingStateChanged`, `onError`, etc.)
/// using `DispatchQueue.main.async`.
///
/// **Why NSObject**: Required for `AVCaptureFileOutputRecordingDelegate` conformance,
/// which provides `fileOutput(_:didStartRecordingTo:from:)` and
/// `fileOutput(_:didFinishRecordingTo:from:error:)` callbacks.
///
/// **Callback pattern**: The ViewModel binds closures in `bindCallbacks()` at init.
/// This avoids Combine/async bridging complexity while keeping the service testable.
///
/// **Sendable invariant**: All mutable state is mutated exclusively from `sessionQueue`
/// (a serial dispatch queue), so the type is safely `@unchecked Sendable`. Do not add
/// mutable state that is touched from any other queue without updating this guarantee.
final class CameraService: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.rgriola.promptcam.session")
    private let movieFileOutput = AVCaptureMovieFileOutput()
    private var currentOutputURL: URL?
    private var videoDevice: AVCaptureDevice?
    private var isSessionConfigured = false

    var onRecordingStateChanged: (@MainActor @Sendable (Bool) -> Void)?
    var onSessionRunningStateChanged: (@MainActor @Sendable (Bool) -> Void)?
    var onFormatApplied: (@MainActor @Sendable (RecordingFormat) -> Void)?
    var onSupportedFormatsQueried: (@MainActor @Sendable ([VideoResolution], [VideoFrameRate]) -> Void)?
    var onError: (@MainActor @Sendable (String) -> Void)?

    static func preferredCameraSelection(frontAvailable: Bool, backAvailable: Bool) -> PreferredCameraSelection {
        if frontAvailable {
            return .front
        }

        if backAvailable {
            return .back
        }

        return .unavailable
    }

    func configureSession(format: RecordingFormat = .default) {
        sessionQueue.async {
            guard !self.isSessionConfigured else { return }
            guard self.session.inputs.isEmpty else {
                self.isSessionConfigured = true
                return
            }

            self.session.beginConfiguration()

            // Apply resolution preset — fall back to .high if device doesn't support requested preset.
            let desiredPreset = format.resolution.sessionPreset
            if self.session.canSetSessionPreset(desiredPreset) {
                self.session.sessionPreset = desiredPreset
            } else {
                self.session.sessionPreset = .high
            }

            defer { self.session.commitConfiguration() }

            do {
                var didAddVideoInput = false
                var didAddMovieOutput = false
                let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                let selection = Self.preferredCameraSelection(
                    frontAvailable: frontCamera != nil,
                    backAvailable: backCamera != nil
                )
                let videoDevice: AVCaptureDevice?

                switch selection {
                case .front:
                    videoDevice = frontCamera
                case .back:
                    videoDevice = backCamera
                case .unavailable:
                    videoDevice = nil
                }

                guard let videoDevice else {
                    self.publishError("No camera device found.")
                    return
                }

                self.videoDevice = videoDevice
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                    didAddVideoInput = true
                }

                if let audioDevice = AVCaptureDevice.default(for: .audio) {
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if self.session.canAddInput(audioInput) {
                        self.session.addInput(audioInput)
                    }
                }

                if self.session.canAddOutput(self.movieFileOutput) {
                    self.session.addOutput(self.movieFileOutput)
                    didAddMovieOutput = true
                }

                guard didAddVideoInput && didAddMovieOutput else {
                    self.publishError("Failed to prepare camera inputs/outputs.")
                    return
                }

                // Apply frame rate after inputs/outputs are wired.
                self.applyFrameRate(format.frameRate, to: videoDevice)

                self.isSessionConfigured = true

                // Query supported formats NOW — videoDevice and preset are set.
                let supported = self.supportedFormats()
                Task { @MainActor in
                    self.onSupportedFormatsQueried?(supported.resolutions, supported.frameRates)
                }
            } catch {
                self.publishError("Failed to configure camera: \(error.localizedDescription)")
            }
        }
    }

    func startSession() {
        sessionQueue.async {
            guard self.isSessionConfigured else {
                self.publishSessionRunningState(false)
                return
            }

            guard !self.session.isRunning else {
                self.publishSessionRunningState(true)
                return
            }
            self.session.startRunning()
            self.publishSessionRunningState(true)
        }
    }

    // MARK: - Format Management

    /// Applies a new recording format to the live session.
    /// No-op if currently recording. Runs on sessionQueue.
    func applyFormat(_ format: RecordingFormat) {
        sessionQueue.async {
            guard self.isSessionConfigured else { return }
            guard !self.movieFileOutput.isRecording else {
                self.publishError("Cannot change format while recording.")
                return
            }

            self.session.beginConfiguration()

            // Resolution
            let desiredPreset = format.resolution.sessionPreset
            if self.session.canSetSessionPreset(desiredPreset) {
                self.session.sessionPreset = desiredPreset
            } else {
                // Fall back — keep current preset, notify caller.
                self.session.sessionPreset = .high
            }

            // Frame rate — apply after preset change, may fall back if unsupported.
            var appliedRate = format.frameRate
            if let device = self.videoDevice {
                appliedRate = self.applyFrameRate(format.frameRate, to: device)
            }

            self.session.commitConfiguration()

            // Report what was actually applied.
            let appliedResolution: VideoResolution = self.session.sessionPreset == .hd4K3840x2160 ? .uhd4K : .hd1080p
            let applied = RecordingFormat(resolution: appliedResolution, frameRate: appliedRate)
            Task { @MainActor in
                self.onFormatApplied?(applied)
            }
        }
    }

    /// Queries the video device's **full hardware capabilities** for supported resolutions and frame rates.
    /// Returns the complete set the device can handle — stable regardless of current active format.
    /// The actual `applyFrameRate` method validates against the active format at apply time.
    func supportedFormats() -> (resolutions: [VideoResolution], frameRates: [VideoFrameRate]) {
        // Must be called after configureSession so videoDevice is set.
        guard let device = videoDevice else {
            return (VideoResolution.allCases, VideoFrameRate.allCases)
        }

        var resolutions: [VideoResolution] = [.hd1080p] // 1080p is universally supported
        if session.canSetSessionPreset(.hd4K3840x2160) {
            resolutions.append(.uhd4K)
        }

        // Scan ALL device formats to determine full hardware FPS capability.
        var frameRates = Set<VideoFrameRate>()
        for deviceFormat in device.formats {
            for range in deviceFormat.videoSupportedFrameRateRanges {
                for rate in VideoFrameRate.allCases {
                    if Double(rate.rawValue) >= range.minFrameRate &&
                       Double(rate.rawValue) <= range.maxFrameRate {
                        frameRates.insert(rate)
                    }
                }
            }
        }

        let sortedRates = frameRates.sorted { $0.rawValue < $1.rawValue }
        return (resolutions, sortedRates.isEmpty ? [.fps30] : sortedRates)
    }

    /// Sets the frame rate on a video device. Returns the actually applied rate (may fall back).
    /// Call within a session configuration block.
    @discardableResult
    private func applyFrameRate(_ rate: VideoFrameRate, to device: AVCaptureDevice) -> VideoFrameRate {
        let desiredFPS = Double(rate.rawValue)

        // Check if the ACTIVE format supports the requested FPS.
        let activeRanges = device.activeFormat.videoSupportedFrameRateRanges
        let supported = activeRanges.contains { desiredFPS >= $0.minFrameRate && desiredFPS <= $0.maxFrameRate }

        let targetRate: VideoFrameRate
        if supported {
            targetRate = rate
        } else {
            // Fall back to the highest supported rate.
            let maxSupported = activeRanges.map(\.maxFrameRate).max() ?? 30
            targetRate = VideoFrameRate.allCases
                .filter { Double($0.rawValue) <= maxSupported }
                .max { $0.rawValue < $1.rawValue } ?? .fps30
            print("[TP] FPS \(rate.rawValue) unsupported by active format, falling back to \(targetRate.rawValue)")
        }

        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetRate.rawValue))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetRate.rawValue))
            device.unlockForConfiguration()
        } catch {
            self.publishError("Failed to set frame rate: \(error.localizedDescription)")
        }

        return targetRate
    }

    func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            self.publishSessionRunningState(false)
        }
    }

    func startRecording() {
        sessionQueue.async {
            guard !self.movieFileOutput.isRecording else { return }
            guard self.isSessionConfigured else {
                self.publishError("Camera is still preparing. Try again in a moment.")
                return
            }
            guard self.session.isRunning else {
                self.publishError("Camera is starting up. Try again in a moment.")
                return
            }
            guard self.movieFileOutput.connection(with: .video) != nil else {
                self.publishError("Camera not ready for recording yet. Try again.")
                return
            }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")

            self.currentOutputURL = outputURL
            self.movieFileOutput.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    func stopRecording() {
        sessionQueue.async {
            guard self.movieFileOutput.isRecording else { return }
            self.movieFileOutput.stopRecording()
        }
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async {
            guard let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }

                device.unlockForConfiguration()
            } catch {
                self.publishError("Failed to set focus/exposure: \(error.localizedDescription)")
            }
        }
    }

    func lockFocusExposure(at devicePoint: CGPoint) {
        lockFocusExposure(at: devicePoint, completion: nil)
    }

    static func lockOutcome(supportsFocusLock: Bool, supportsExposureLock: Bool) -> FocusExposureLockOutcome {
        if supportsFocusLock && supportsExposureLock {
            return .afAeLocked
        }

        if supportsExposureLock {
            return .aeLocked
        }

        if supportsFocusLock {
            return .afLocked
        }

        return .unsupported
    }

    func lockFocusExposure(at devicePoint: CGPoint, completion: (@MainActor @Sendable (FocusExposureLockOutcome) -> Void)? = nil) {
        sessionQueue.async {
            guard let device = self.videoDevice else {
                self.publishLockOutcome(.unsupported, completion: completion)
                return
            }

            do {
                try device.lockForConfiguration()

                defer {
                    device.unlockForConfiguration()
                }

                let supportsFocusLock = device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.locked)
                let supportsExposureLock = device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.locked)
                let outcome = Self.lockOutcome(supportsFocusLock: supportsFocusLock, supportsExposureLock: supportsExposureLock)

                guard outcome != .unsupported else {
                    self.publishLockOutcome(.unsupported, completion: completion)
                    return
                }

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    if supportsFocusLock {
                        device.focusMode = .locked
                    }
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    if supportsExposureLock {
                        device.exposureMode = .locked
                    }
                }

                self.publishLockOutcome(outcome, completion: completion)
            } catch {
                self.publishError("Failed to lock focus/exposure: \(error.localizedDescription)")
                self.publishLockOutcome(.unsupported, completion: completion)
            }
        }
    }

    func unlockFocusExposure() {
        sessionQueue.async {
            guard let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                device.unlockForConfiguration()
            } catch {
                self.publishError("Failed to unlock focus/exposure: \(error.localizedDescription)")
            }
        }
    }

    func adjustExposure(by delta: Float) {
        sessionQueue.async {
            guard let device = self.videoDevice else { return }
            let minBias = device.minExposureTargetBias
            let maxBias = device.maxExposureTargetBias
            let nextBias = min(max(device.exposureTargetBias + delta, minBias), maxBias)

            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(nextBias) { _ in }
                device.unlockForConfiguration()
            } catch {
                self.publishError("Failed to adjust exposure: \(error.localizedDescription)")
            }
        }
    }

    /// Sets exposure bias to an absolute value, bypassing delta accumulation.
    /// Reliable for reset — reads device min/max to clamp, then sets directly.
    func setExposure(to value: Float) {
        sessionQueue.async {
            guard let device = self.videoDevice else { return }
            let clamped = min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped) { _ in }
                device.unlockForConfiguration()
            } catch {
                self.publishError("Failed to set exposure: \(error.localizedDescription)")
            }
        }
    }

    private func saveRecordingToPhotoLibrary(_ outputFileURL: URL) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            self.publishError("Photo library permission is required to save recordings. Please grant access in Settings.")
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        } completionHandler: { success, error in
            if let error {
                self.publishError("Failed to save video: \(error.localizedDescription)")
            } else if !success {
                self.publishError("Video save operation did not complete.")
            }

            try? FileManager.default.removeItem(at: outputFileURL)
        }
    }

    private func publishRecordingState(_ isRecording: Bool) {
        Task { @MainActor in
            self.onRecordingStateChanged?(isRecording)
        }
    }

    private func publishError(_ message: String) {
        Task { @MainActor in
            self.onError?(message)
        }
    }

    private func publishSessionRunningState(_ isRunning: Bool) {
        Task { @MainActor in
            self.onSessionRunningStateChanged?(isRunning)
        }
    }

    private func publishLockOutcome(_ outcome: FocusExposureLockOutcome, completion: (@MainActor @Sendable (FocusExposureLockOutcome) -> Void)?) {
        guard let completion else { return }

        Task { @MainActor in
            completion(outcome)
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        publishRecordingState(true)
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        publishRecordingState(false)

        if let error {
            publishError("Recording failed: \(error.localizedDescription)")
            return
        }

        saveRecordingToPhotoLibrary(outputFileURL)
    }
}
