// May 29, 2026 - 11:23pm - GitHub Copilot
import AVFoundation
import Photos

enum FocusExposureLockOutcome: Equatable {
    case afAeLocked
    case aeLocked
    case afLocked
    case unsupported
}

final class CameraService: NSObject {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.rgriola.promptcam.session")
    private let movieFileOutput = AVCaptureMovieFileOutput()
    private var currentOutputURL: URL?
    private var videoDevice: AVCaptureDevice?

    var onRecordingStateChanged: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    func configureSession() {
        sessionQueue.async {
            guard self.session.inputs.isEmpty else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            defer { self.session.commitConfiguration() }

            do {
                guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ??
                        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                else {
                    self.publishError("No camera device found.")
                    return
                }

                self.videoDevice = videoDevice
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                }

                if let audioDevice = AVCaptureDevice.default(for: .audio) {
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if self.session.canAddInput(audioInput) {
                        self.session.addInput(audioInput)
                    }
                }

                if self.session.canAddOutput(self.movieFileOutput) {
                    self.session.addOutput(self.movieFileOutput)
                }
            } catch {
                self.publishError("Failed to configure camera: \(error.localizedDescription)")
            }
        }
    }

    func startSession() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func startRecording() {
        sessionQueue.async {
            guard !self.movieFileOutput.isRecording else { return }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")

            self.currentOutputURL = outputURL
            self.movieFileOutput.startRecording(to: outputURL, recordingDelegate: self)
            self.publishRecordingState(true)
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
