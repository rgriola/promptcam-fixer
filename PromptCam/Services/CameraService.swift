// May 30, 2026 - 4:23pm - GitHub Copilot
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

final class CameraService: NSObject {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.rgriola.promptcam.session")
    private let movieFileOutput = AVCaptureMovieFileOutput()
    private var currentOutputURL: URL?
    private var videoDevice: AVCaptureDevice?
    private var isSessionConfigured = false

    var onRecordingStateChanged: ((Bool) -> Void)?
    var onSessionRunningStateChanged: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    static func preferredCameraSelection(frontAvailable: Bool, backAvailable: Bool) -> PreferredCameraSelection {
        if frontAvailable {
            return .front
        }

        if backAvailable {
            return .back
        }

        return .unavailable
    }

    func configureSession() {
        sessionQueue.async {
            guard !self.isSessionConfigured else { return }
            guard self.session.inputs.isEmpty else {
                self.isSessionConfigured = true
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

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

                self.isSessionConfigured = true
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

    func lockFocusExposure(at devicePoint: CGPoint, completion: ((FocusExposureLockOutcome) -> Void)? = nil) {
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

    private func saveRecordingToPhotoLibrary(_ outputFileURL: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.publishError("Photo library permission is required to save recordings.")
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
    }

    private func publishRecordingState(_ isRecording: Bool) {
        DispatchQueue.main.async {
            self.onRecordingStateChanged?(isRecording)
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.onError?(message)
        }
    }

    private func publishSessionRunningState(_ isRunning: Bool) {
        DispatchQueue.main.async {
            self.onSessionRunningStateChanged?(isRunning)
        }
    }

    private func publishLockOutcome(_ outcome: FocusExposureLockOutcome, completion: ((FocusExposureLockOutcome) -> Void)?) {
        guard let completion else { return }

        DispatchQueue.main.async {
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
