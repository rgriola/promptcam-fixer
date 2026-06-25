// CameraService+Controls.swift
// PromptCam
//
// Extracted from CameraService.swift — focus, exposure, and lock controls.

import AVFoundation

// MARK: - Focus, Exposure & Lock Controls

extension CameraService {

    // MARK: - Cinematic Mode Guard

    /// Returns true when the session is actively capturing in Cinematic Video mode.
    ///
    /// Apple requires `.continuousAutoFocus` at all times during cinematic capture.
    /// Setting `.autoFocus` or `.locked` throws an uncatchable `NSInvalidArgumentException`.
    /// Any focus/lock call must check this flag and skip the `focusMode` assignment.
    ///
    /// - iOS 26+: reads `isCinematicVideoCaptureEnabled` directly from the capture input.
    /// - Pre-iOS 26: infers cinematic mode from the active format's depth data support
    ///   (depth formats are only present on CINE-capable formats on TrueDepth cameras).
    var isCinematicActive: Bool {
        if #available(iOS 26.0, *) {
            return videoInput?.isCinematicVideoCaptureEnabled == true
        } else {
            // Depth data support is the best pre-iOS-26 proxy for cinematic formats.
            return videoDevice?.activeFormat.supportedDepthDataFormats.isEmpty == false
        }
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async {
            guard let device = self.videoDevice else { return }

            // Cinematic Mode manages continuous AF automatically.
            // Setting any other focus mode throws NSInvalidArgumentException.
            guard !self.isCinematicActive else {
                Log.camera.debug("CameraService: focus(at:) skipped — cinematic mode active")
                return
            }

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
                self.publishError(.focusExposureFailed(error.localizedDescription))
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

            // Cinematic Mode manages continuous AF automatically.
            // Setting .locked or .autoFocus throws NSInvalidArgumentException.
            guard !self.isCinematicActive else {
                Log.camera.debug("CameraService: lockFocusExposure(at:) skipped — cinematic mode active")
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
                self.publishError(.focusExposureFailed(error.localizedDescription))
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
                self.publishError(.focusExposureFailed(error.localizedDescription))
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
                self.publishError(.focusExposureFailed(error.localizedDescription))
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
                self.publishError(.focusExposureFailed(error.localizedDescription))
            }
        }
    }
}
