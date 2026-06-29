// CameraService+Format.swift
// PromptCam
//
// Extracted from CameraService.swift — format management, cinematic capture, and diagnostics.

import AVFoundation

// MARK: - Format Management & Cinematic

extension CameraService {

    // MARK: - Format Management

    /// Applies a new recording format to the live session.
    /// No-op if currently recording. Runs on sessionQueue.
    func applyFormat(_ format: RecordingFormat) {
        sessionQueue.async {
            guard self.isSessionConfigured else { return }
            guard !self.movieFileOutput.isRecording else {
                self.publishError(.formatChangeDuringRecording)
                return
            }

            self.session.beginConfiguration()

            // Track whether cinematic mode was actually applied.
            var appliedMode = format.mode

            // Save previous input for rollback if the swap fails.
            let previousInput = self.videoInput
            let previousDevice = self.videoDevice

            // Swap the physical camera if the mode or resolution changed.
            // Routes to whichever front device has the best CINE format for the resolution.
            let targetDevice = self.preferredDevice(for: format.mode, resolution: format.resolution)
            if let targetDevice = targetDevice,
               self.videoDevice?.uniqueID != targetDevice.uniqueID {
                // Remove current video input.
                if let oldInput = self.videoInput {
                    self.session.removeInput(oldInput)
                    self.videoInput = nil
                    self.videoDevice = nil
                }
                // Add new video input.
                do {
                    let newInput = try AVCaptureDeviceInput(device: targetDevice)
                    if self.session.canAddInput(newInput) {
                        self.session.addInput(newInput)
                        self.videoDevice = targetDevice
                        self.videoInput = newInput
                        Log.camera.info("Swapped to \(targetDevice.localizedName, privacy: .public) for \(format.mode.rawValue, privacy: .public) mode")
                    } else {
                        // Rollback: restore previous input to avoid black screen.
                        if let previousInput, self.session.canAddInput(previousInput) {
                            self.session.addInput(previousInput)
                            self.videoInput = previousInput
                            self.videoDevice = previousDevice
                        }
                        self.publishError(.formatUnavailable("Cannot use \(targetDevice.localizedName) for \(format.mode.rawValue) mode."))
                        appliedMode = .standard
                    }
                } catch {
                    // Rollback: restore previous input to avoid black screen.
                    if let previousInput, self.session.canAddInput(previousInput) {
                        self.session.addInput(previousInput)
                        self.videoInput = previousInput
                        self.videoDevice = previousDevice
                    }
                    self.publishError(.inputConfigurationFailed)
                    appliedMode = .standard
                }
            }

            // Set cinematic format on TrueDepth device, or use session preset for standard.
            if appliedMode == .cinematic, let device = self.videoDevice {
                if let cinematicFormat = self.findCinematicFormat(
                    for: device, resolution: format.resolution, frameRate: format.frameRate
                ) {
                    do {
                        try device.lockForConfiguration()
                        device.activeFormat = cinematicFormat
                        device.unlockForConfiguration()
                        if #available(iOS 26.0, *), let input = self.videoInput,
                           input.isCinematicVideoCaptureSupported {
                            self.enableCinematicCapture(on: input)
                        }
                    } catch {
                        self.publishError(.formatUnavailable(error.localizedDescription))
                        appliedMode = .standard
                        self.disableCinematicCapture()
                    }
                } else {
                    self.publishError(.formatUnavailable("No cinematic format available on this device."))
                    appliedMode = .standard
                    self.disableCinematicCapture()
                }
            } else {
                self.disableCinematicCapture()
            }

            // Resolution preset — only for standard mode. Cinematic format is set above.
            if appliedMode == .standard {
                let desiredPreset = format.resolution.sessionPreset
                if self.session.canSetSessionPreset(desiredPreset) {
                    self.session.sessionPreset = desiredPreset
                } else {
                    self.session.sessionPreset = .high
                }
            }

            // Frame rate — apply after preset change, may fall back if unsupported.
            var appliedRate = format.frameRate
            if let device = self.videoDevice {
                appliedRate = self.applyFrameRate(format.frameRate, to: device)
            }

            self.session.commitConfiguration()

            // Report what was actually applied.
            // For cinematic, read resolution from the active format dimensions (session preset
            // is not set in cinematic mode and would give the wrong answer).
            // For standard, use the session preset as before.
            let appliedResolution: VideoResolution
            if appliedMode == .cinematic, let device = self.videoDevice {
                let dim = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                appliedResolution = dim.height >= 2160 ? .uhd4K : .hd1080p
            } else {
                appliedResolution = self.session.sessionPreset == .hd4K3840x2160 ? .uhd4K : .hd1080p
            }
            let applied = RecordingFormat(resolution: appliedResolution, frameRate: appliedRate, mode: appliedMode)
            Task { @MainActor in
                self.onFormatApplied?(applied)
            }
        }
    }

    /// Queries the device's full capabilities including cinematic mode support.
    /// Returns mode-specific format availability for proper UI validation.
    func queryDeviceCapabilities() -> DeviceCapabilities {
        // Standard capabilities come from the wide-angle front camera.
        let wideAngle = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? videoDevice

        // Scan ALL front-facing cameras for CINE formats — different devices carry CINE
        // on different hardware (TrueDepth on iPhone 13, UltraWide on iPhone 17 Pro).
        let frontDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.allVideoDeviceTypes(),
            mediaType: .video,
            position: .front
        )

        // HD/4K pixel threshold (midpoint between 1080p and 4K).
        let hdThreshold: Int64 = 5_184_000

        // MARK: Cinematic format discovery
        // For each CINE-capable format, record the (resolution, fps) pairs it supports.
        var cinematicPairSet = Set<RecordingFormat>()
        var supportsCinematic = false

        for device in frontDiscovery.devices {
            for fmt in device.formats {
                let isCine: Bool
                if #available(iOS 26.0, *) { isCine = fmt.minSimulatedAperture != 0 }
                else { isCine = !fmt.supportedDepthDataFormats.isEmpty }
                guard isCine else { continue }

                supportsCinematic = true
                let dim = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                let pixels = Int64(dim.width) * Int64(dim.height)
                let resolution: VideoResolution = pixels <= hdThreshold ? .hd1080p : .uhd4K

                for range in fmt.videoSupportedFrameRateRanges {
                    for rate in VideoFrameRate.allCases {
                        if Double(rate.rawValue) >= range.minFrameRate &&
                           Double(rate.rawValue) <= range.maxFrameRate {
                            cinematicPairSet.insert(
                                RecordingFormat(resolution: resolution, frameRate: rate, mode: .cinematic)
                            )
                        }
                    }
                }
            }
        }

        // Fallback: if CINE-capable but no pairs matched the threshold, assume HD 24/30p.
        if supportsCinematic && cinematicPairSet.isEmpty {
            cinematicPairSet.insert(RecordingFormat(resolution: .hd1080p, frameRate: .fps24, mode: .cinematic))
            cinematicPairSet.insert(RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .cinematic))
        }

        let cinematicFormats = cinematicPairSet.sorted {
            if $0.resolution.rawValue != $1.resolution.rawValue { return $0.resolution.rawValue < $1.resolution.rawValue }
            return $0.frameRate.rawValue < $1.frameRate.rawValue
        }

        Log.camera.info("CINE pairs: \(cinematicFormats.map { "\($0.resolution.rawValue) \($0.frameRate.rawValue)p" }, privacy: .public)")

        // MARK: Standard format discovery
        // For each format on the wide-angle camera, record (resolution, fps) pairs.
        guard let device = wideAngle else {
            Log.camera.warning("No wide-angle device — returning minimal capabilities")
            return DeviceCapabilities(
                supportsCinematicMode: supportsCinematic,
                standardFormats: [RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .standard)],
                cinematicFormats: cinematicFormats
            )
        }

        var standardPairSet = Set<RecordingFormat>()
        let can4K = session.canSetSessionPreset(.hd4K3840x2160)

        for fmt in device.formats {
            let dim = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            let pixels = Int64(dim.width) * Int64(dim.height)

            // Map to our resolution buckets; skip anything that isn't HD or 4K.
            let resolution: VideoResolution
            if pixels <= hdThreshold {
                resolution = .hd1080p
            } else if can4K {
                resolution = .uhd4K
            } else {
                continue
            }

            for range in fmt.videoSupportedFrameRateRanges {
                for rate in VideoFrameRate.allCases {
                    if Double(rate.rawValue) >= range.minFrameRate &&
                       Double(rate.rawValue) <= range.maxFrameRate {
                        standardPairSet.insert(
                            RecordingFormat(resolution: resolution, frameRate: rate, mode: .standard)
                        )
                    }
                }
            }
        }

        // Always guarantee at least HD 30p.
        if standardPairSet.isEmpty {
            standardPairSet.insert(RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .standard))
        }

        let standardFormats = standardPairSet.sorted {
            if $0.resolution.rawValue != $1.resolution.rawValue { return $0.resolution.rawValue < $1.resolution.rawValue }
            return $0.frameRate.rawValue < $1.frameRate.rawValue
        }

        Log.camera.info("STD pairs: \(standardFormats.map { "\($0.resolution.rawValue) \($0.frameRate.rawValue)p" }, privacy: .public)")

        return DeviceCapabilities(
            supportsCinematicMode: supportsCinematic,
            standardFormats: standardFormats,
            cinematicFormats: cinematicFormats
        )
    }

    // MARK: - Cinematic Format Discovery

    /// Finds a CINE-capable format on the given device matching the requested resolution and frame rate.
    /// Only searches the device's own formats — no companion-device lookup.
    /// Finds the best CINE-capable format on the given device for the requested resolution and fps.
    /// Uses a fixed pixel threshold (5.2MP) to split HD vs 4K size classes, then picks
    /// the format closest to the standard target pixels (1920x1080 or 3840x2160) within that class.
    func findCinematicFormat(
        for device: AVCaptureDevice,
        resolution: VideoResolution,
        frameRate: VideoFrameRate
    ) -> AVCaptureDevice.Format? {
        let desiredFPS = Double(frameRate.rawValue)
        let targetPixels: Int64
        switch resolution {
        case .hd1080p: targetPixels = 1920 * 1080   // 2,073,600
        case .uhd4K:   targetPixels = 3840 * 2160   // 8,294,400
        }
        // Midpoint between HD and 4K target pixel counts.
        let hdThreshold: Int64 = 5_184_000

        // Collect all CINE formats on this device.
        var cineFormats: [(format: AVCaptureDevice.Format, pixels: Int64)] = []
        for fmt in device.formats {
            let isCine: Bool
            if #available(iOS 26.0, *) { isCine = fmt.minSimulatedAperture != 0 }
            else { isCine = !fmt.supportedDepthDataFormats.isEmpty }
            guard isCine else { continue }
            let dim = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            let pixels = Int64(dim.width) * Int64(dim.height)
            let fpsStr = fmt.videoSupportedFrameRateRanges
                .map { String(format: "%.0f-%.0ffps", $0.minFrameRate, $0.maxFrameRate) }
                .joined(separator: "/")
            Log.camera.info("  CINE candidate: \(dim.width, privacy: .public)x\(dim.height, privacy: .public) \(fpsStr, privacy: .public) on \(device.localizedName, privacy: .public)")
            cineFormats.append((fmt, pixels))
        }

        guard !cineFormats.isEmpty else {
            Log.camera.warning("No CINE formats on \(device.localizedName, privacy: .public)")
            return nil
        }

        // Filter to the size class matching the requested resolution.
        let sizeGroup: [(format: AVCaptureDevice.Format, pixels: Int64)]
        switch resolution {
        case .hd1080p:
            let hdGroup = cineFormats.filter { $0.pixels <= hdThreshold }
            sizeGroup = hdGroup.isEmpty ? cineFormats : hdGroup
        case .uhd4K:
            let k4Group = cineFormats.filter { $0.pixels > hdThreshold }
            sizeGroup = k4Group.isEmpty ? cineFormats : k4Group
        }

        // Within the size class, sort by proximity to the standard target pixel count.
        // Prefer format whose dimensions most closely match 1920x1080 or 3840x2160.
        let sorted = sizeGroup.sorted { abs($0.pixels - targetPixels) < abs($1.pixels - targetPixels) }

        // Pick the closest-dimension format that supports the desired fps.
        if let match = sorted.first(where: { entry in
            entry.format.videoSupportedFrameRateRanges.contains {
                desiredFPS >= $0.minFrameRate && desiredFPS <= $0.maxFrameRate
            }
        }) {
            let dim = CMVideoFormatDescriptionGetDimensions(match.format.formatDescription)
            Log.camera.info("CINE match (\(resolution.rawValue, privacy: .public)): \(dim.width, privacy: .public)x\(dim.height, privacy: .public) @ \(desiredFPS, privacy: .public)fps")
            return match.format
        }

        // fps fallback: best-dimension format with max fps closest to desired.
        if let fallback = sorted.min(by: { a, b in
            let aMax = a.format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            let bMax = b.format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return abs(aMax - desiredFPS) < abs(bMax - desiredFPS)
        }) {
            let dim = CMVideoFormatDescriptionGetDimensions(fallback.format.formatDescription)
            Log.camera.notice("CINE fps fallback (\(resolution.rawValue, privacy: .public)): \(dim.width, privacy: .public)x\(dim.height, privacy: .public)")
            return fallback.format
        }

        Log.camera.warning("findCinematicFormat: no match for \(resolution.rawValue, privacy: .public) @ \(frameRate.rawValue, privacy: .public)fps on \(device.localizedName, privacy: .public)")
        return nil
    }
    
    // MARK: - Diagnostic Logging
    
    /// Logs all available formats for every camera (front + back) on first session configure.
    /// Output appears in Xcode console and Console.app under subsystem com.rgriola.promptcam.
    func logAllCameraFormats() {
        let deviceTypes = Self.allVideoDeviceTypes()
        
        for position in [AVCaptureDevice.Position.front, .back] {
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: position
            )
            let positionLabel = position == .front ? "FRONT" : "BACK"
            Log.camera.info("=== \(positionLabel, privacy: .public) CAMERAS (\(session.devices.count, privacy: .public) device(s)) ===")
            
            for device in session.devices {
                Log.camera.info("  Device: \(device.localizedName, privacy: .public) | Type: \(device.deviceType.rawValue, privacy: .public) | Aperture: f/\(device.lensAperture, privacy: .public)")
                
                var cinematicCount = 0
                var depthCount = 0
                
                for (i, format) in device.formats.enumerated() {
                    let dim = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    let fpsRanges = format.videoSupportedFrameRateRanges.map {
                        String(format: "%.0f-%.0ffps", $0.minFrameRate, $0.maxFrameRate)
                    }.joined(separator: ", ")
                    let depthCount_ = format.supportedDepthDataFormats.count
                    let hasPortrait = format.isPortraitEffectsMatteStillImageDeliverySupported
                    let isHDR = format.isVideoHDRSupported
                    
                    var flags: [String] = []
                    if #available(iOS 26.0, *) {
                        // minSimulatedAperture != 0 is the definitive cinematic indicator (iOS 26+).
                        if format.minSimulatedAperture != 0 {
                            let aperStr = String(format: "f/%.1f-%.1f def:%.1f",
                                format.minSimulatedAperture,
                                format.maxSimulatedAperture,
                                format.defaultSimulatedAperture)
                            flags.append("CINE(\(aperStr))")
                            cinematicCount += 1
                        }
                    } else {
                        // Pre-iOS 26: use depth/portrait as proxy.
                        if !format.supportedDepthDataFormats.isEmpty ||
                           format.isPortraitEffectsMatteStillImageDeliverySupported {
                            flags.append("CINE-PROXY")
                            cinematicCount += 1
                        }
                    }
                    if depthCount_ > 0 {
                        flags.append("DEPTH(\(depthCount_))")
                        depthCount += 1
                    }
                    if hasPortrait { flags.append("PORTRAIT") }
                    if isHDR { flags.append("HDR") }
                    
                    let flagStr = flags.isEmpty ? "" : " [\(flags.joined(separator: " "))]"
                    Log.camera.info("    [\(i, privacy: .public)] \(dim.width, privacy: .public)x\(dim.height, privacy: .public) \(fpsRanges, privacy: .public)\(flagStr, privacy: .public)")
                }
                
                Log.camera.info("  → \(device.formats.count, privacy: .public) total formats | \(cinematicCount, privacy: .public) cinematic | \(depthCount, privacy: .public) with depth")
            }
        }
        Log.camera.info("=== END CAMERA FORMAT DUMP ===")
    }
    
    /// Returns all video device types supported on the current iOS version.
    /// Deployment target is iOS 18, so the iOS 13 multi-camera types are always available.
    static func allVideoDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInTrueDepthCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera
        ]
        if #available(iOS 17.0, *) {
            types.append(.builtInLiDARDepthCamera)
        }
        return types
    }

    // MARK: - Cinematic Aperture Control

    /// Enables AVFoundation cinematic video capture on the given input and fires
    /// `onCinematicApertureAvailable` with the device's (min, max, default) simulated aperture.
    /// Must be called inside a `beginConfiguration` / `commitConfiguration` block.
    /// The system manages format selection internally — no manual activeFormat swap needed.
    @available(iOS 26.0, *)
    func enableCinematicCapture(on input: AVCaptureDeviceInput) {
        input.isCinematicVideoCaptureEnabled = true
        Log.camera.info("Cinematic video capture ENABLED on \(input.device.localizedName, privacy: .public)")

        // Aperture range comes from the device's active format after the system configures it.
        let fmt = input.device.activeFormat
        let minAp = fmt.minSimulatedAperture
        let maxAp = fmt.maxSimulatedAperture
        let defAp = fmt.defaultSimulatedAperture

        guard minAp != 0 else {
            Log.camera.warning("Format minSimulatedAperture=0 — no aperture slider on this device")
            return
        }
        Log.camera.info("Aperture range: f/\(minAp, privacy: .public) – f/\(maxAp, privacy: .public), default f/\(defAp, privacy: .public)")

        Task { @MainActor in
            self.onCinematicApertureAvailable?(minAp, maxAp, defAp)
        }
    }

    /// Disables cinematic capture on the stored input and signals the UI to hide the aperture control.
    func disableCinematicCapture() {
        if #available(iOS 26.0, *) {
            if let input = videoInput, input.isCinematicVideoCaptureSupported {
                input.isCinematicVideoCaptureEnabled = false
                Log.camera.info("Cinematic video capture DISABLED")
            }
        }
        Task { @MainActor in
            // (0, 0, 0) signals ViewModel to clear the aperture panel.
            self.onCinematicApertureAvailable?(0, 0, 0)
        }
    }

    /// Sets the live simulated aperture (f-stop) for cinematic depth-of-field blur.
    /// No-op on pre-iOS 26 or when cinematic mode is not active.
    /// Must be called before `startRecording` — blocked during active recording.
    func setSimulatedAperture(_ value: Float) {
        guard #available(iOS 26.0, *) else { return }
        sessionQueue.async {
            guard let input = self.videoInput,
                  input.isCinematicVideoCaptureSupported,
                  input.isCinematicVideoCaptureEnabled else { return }
            guard !self.movieFileOutput.isRecording else {
                Log.camera.warning("Cannot change simulated aperture while recording")
                return
            }
            let fmt = input.device.activeFormat
            guard fmt.minSimulatedAperture != 0 else { return }
            let clamped = min(max(value, fmt.minSimulatedAperture), fmt.maxSimulatedAperture)
            input.simulatedAperture = clamped
            Log.camera.info("Simulated aperture → f/\(clamped, privacy: .public)")
        }
    }

    /// Sets the frame rate on a video device. Returns the actually applied rate (may fall back).
    /// Call within a session configuration block.
    @discardableResult
    func applyFrameRate(_ rate: VideoFrameRate, to device: AVCaptureDevice) -> VideoFrameRate {
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
            Log.camera.notice("FPS \(rate.rawValue, privacy: .public) unsupported by active format, falling back to \(targetRate.rawValue, privacy: .public)")
        }

        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetRate.rawValue))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetRate.rawValue))
            device.unlockForConfiguration()
        } catch {
            self.publishError(.frameRateFailed(error.localizedDescription))
        }

        return targetRate
    }
}
