// May 30, 2026 - 4:23pm - GitHub Copilot
// June 8, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add setExposure(to:) for reliable absolute reset
import AVFoundation
import Photos
enum FocusExposureLockOutcome: Equatable, Sendable {
    case afAeLocked
    case aeLocked
    case afLocked
    case unsupported
}

enum PreferredCameraSelection: Equatable, Sendable {
    case front
    case back
    case unavailable
}

// MARK: - Device Capabilities

/// Describes video format capabilities for the current device.
struct DeviceCapabilities: Equatable, Sendable {
    /// Whether the device supports cinematic mode (depth capture).
    let supportsCinematicMode: Bool
    
    /// Supported resolutions for standard video mode.
    let standardResolutions: [VideoResolution]
    
    /// Supported frame rates for standard video mode.
    let standardFrameRates: [VideoFrameRate]
    
    /// Supported resolutions for cinematic mode (typically only 1080p).
    let cinematicResolutions: [VideoResolution]
    
    /// Supported frame rates for cinematic mode (typically 24/30fps only).
    let cinematicFrameRates: [VideoFrameRate]
    
    /// Returns supported resolutions for a given mode.
    func resolutions(for mode: VideoMode) -> [VideoResolution] {
        mode == .cinematic ? cinematicResolutions : standardResolutions
    }
    
    /// Returns supported frame rates for a given mode.
    func frameRates(for mode: VideoMode) -> [VideoFrameRate] {
        mode == .cinematic ? cinematicFrameRates : standardFrameRates
    }
    
    /// Returns whether a specific format combination is supported.
    func isSupported(_ format: RecordingFormat) -> Bool {
        let resolutions = resolutions(for: format.mode)
        let frameRates = frameRates(for: format.mode)
        return resolutions.contains(format.resolution) && frameRates.contains(format.frameRate)
    }
    
    /// Adjusts a format to the nearest valid combination for this device.
    func adjusted(_ format: RecordingFormat) -> RecordingFormat {
        var adjusted = format
        
        // If cinematic mode not supported, fall back to standard.
        if format.mode == .cinematic && !supportsCinematicMode {
            adjusted.mode = .standard
        }
        
        let validResolutions = resolutions(for: adjusted.mode)
        let validFrameRates = frameRates(for: adjusted.mode)
        
        // Adjust resolution if not supported.
        if !validResolutions.contains(adjusted.resolution) {
            adjusted.resolution = validResolutions.first ?? .hd1080p
        }
        
        // Adjust frame rate if not supported.
        if !validFrameRates.contains(adjusted.frameRate) {
            adjusted.frameRate = validFrameRates.first ?? .fps30
        }
        
        return adjusted
    }
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
    /// Retained so we can toggle cinematicVideoCaptureEnabled and set simulatedAperture.
    private var videoInput: AVCaptureDeviceInput?
    private var isSessionConfigured = false

    var onRecordingStateChanged: (@MainActor @Sendable (Bool) -> Void)?
    var onSessionRunningStateChanged: (@MainActor @Sendable (Bool) -> Void)?
    var onFormatApplied: (@MainActor @Sendable (RecordingFormat) -> Void)?
    var onSupportedFormatsQueried: (@MainActor @Sendable ([VideoResolution], [VideoFrameRate]) -> Void)?
    var onDeviceCapabilitiesQueried: (@MainActor @Sendable (DeviceCapabilities) -> Void)?
    /// Fired when cinematic mode is enabled with the device's (min, max, default) simulated aperture.
    /// Fired with (0, 0, 0) when cinematic is disabled — signals UI to hide the aperture control.
    var onCinematicApertureAvailable: (@MainActor @Sendable (Float, Float, Float) -> Void)?
    var onError: (@MainActor @Sendable (String) -> Void)?

    static func preferredCameraSelection(frontAvailable: Bool, backAvailable: Bool) -> PreferredCameraSelection {
        if frontAvailable {
            return .front
        }

        /* if backAvailable {
            return .back
        }
        */

        return .unavailable
    }

    /// Returns the preferred physical device for a given video mode.
    /// Standard → front wide-angle. Cinematic → front TrueDepth (which has CINE formats).
    /// Finds the front-facing device whose CINE formats are closest to the requested
    /// resolution's standard pixel count. Scans ALL front cameras (TrueDepth, UltraWide, etc.)
    /// so whichever physical camera actually has the best HD or 4K CINE format is used.
    /// e.g. iPhone 17 Pro: UltraWide has 1920x1080 CINE → use UltraWide for HD cinematic.
    ///      iPhone 13:      TrueDepth has 1920x1080 CINE → use TrueDepth for HD cinematic.
    private func bestCinematicDevice(for resolution: VideoResolution) -> AVCaptureDevice? {
        let targetPixels: Int64
        switch resolution {
        case .hd1080p: targetPixels = 1920 * 1080   // 2,073,600
        case .uhd4K:   targetPixels = 3840 * 2160   // 8,294,400
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: allVideoDeviceTypes(),
            mediaType: .video,
            position: .front
        )

        var bestDevice: AVCaptureDevice? = nil
        var bestDistance = Int64.max

        for device in discoverySession.devices {
            for fmt in device.formats {
                let isCine: Bool
                if #available(iOS 26.0, *) { isCine = fmt.minSimulatedAperture != 0 }
                else { isCine = !fmt.supportedDepthDataFormats.isEmpty }
                guard isCine else { continue }
                let dim = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                let distance = abs(Int64(dim.width) * Int64(dim.height) - targetPixels)
                if distance < bestDistance {
                    bestDistance = distance
                    bestDevice = device
                }
            }
        }
        Log.camera.info("bestCinematicDevice(\(resolution.rawValue, privacy: .public)) → \(bestDevice?.localizedName ?? "none", privacy: .public) (distance \(bestDistance, privacy: .public)px)")
        return bestDevice
    }

    /// Returns the preferred physical device for a given video mode and resolution.
    /// Standard → front wide-angle. Cinematic → front camera with the best matching CINE format.
    private func preferredDevice(for mode: VideoMode, resolution: VideoResolution = .hd1080p) -> AVCaptureDevice? {
        switch mode {
        case .standard:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        case .cinematic:
            return bestCinematicDevice(for: resolution)
                ?? AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    /// Discovers the best available camera device for the requested format.
    private func discoverCamera(for format: RecordingFormat) -> AVCaptureDevice? {
        preferredDevice(for: format.mode, resolution: format.resolution)
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
                
                // Use discovery session to find the best camera for the requested mode.
                let videoDevice = self.discoverCamera(for: format)
                
                guard let videoDevice else {
                    self.publishError("No camera device found.")
                    return
                }

                self.videoDevice = videoDevice
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                    self.videoInput = videoInput
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

                // Set cinematic format explicitly when using TrueDepth camera.
                // For standard mode, the session preset handles resolution.
                var initialMode = format.mode
                if format.mode == .cinematic {
                    if let cinematicFormat = self.findCinematicFormat(
                        for: videoDevice, resolution: format.resolution, frameRate: format.frameRate
                    ) {
                        do {
                            try videoDevice.lockForConfiguration()
                            videoDevice.activeFormat = cinematicFormat
                            videoDevice.unlockForConfiguration()
                            if #available(iOS 26.0, *), videoInput.isCinematicVideoCaptureSupported {
                                self.enableCinematicCapture(on: videoInput)
                            }
                        } catch {
                            self.publishError("Failed to set cinematic format: \(error.localizedDescription)")
                            initialMode = .standard
                            self.disableCinematicCapture()
                        }
                    } else {
                        Log.camera.info("No cinematic format found, falling back to standard.")
                        initialMode = .standard
                        self.disableCinematicCapture()
                    }
                } else {
                    self.disableCinematicCapture()
                }

                // Apply frame rate after inputs/outputs are wired.
                self.applyFrameRate(format.frameRate, to: videoDevice)

                self.isSessionConfigured = true

                // Dump all camera formats on first configure — visible in Xcode console.
                self.logAllCameraFormats()

                // Query device capabilities (includes mode-specific format support).
                let capabilities = self.queryDeviceCapabilities()
                
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        // For backward compatibility, also call the old supported formats callback.
                        self.onSupportedFormatsQueried?(capabilities.standardResolutions, capabilities.standardFrameRates)
                        self.onDeviceCapabilitiesQueried?(capabilities)
                    }
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

            // Track whether cinematic mode was actually applied.
            var appliedMode = format.mode

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
                        self.publishError("Cannot use \(targetDevice.localizedName) for \(format.mode.rawValue) mode.")
                        appliedMode = .standard
                    }
                } catch {
                    self.publishError("Device swap failed: \(error.localizedDescription)")
                    appliedMode = .standard
                }
            }

            // Set cinematic format on TrueDepth device, or use session preset for standard.
            var appliedCinematicFormat: AVCaptureDevice.Format? = nil
            if appliedMode == .cinematic, let device = self.videoDevice {
                if let cinematicFormat = self.findCinematicFormat(
                    for: device, resolution: format.resolution, frameRate: format.frameRate
                ) {
                    do {
                        try device.lockForConfiguration()
                        device.activeFormat = cinematicFormat
                        device.unlockForConfiguration()
                        appliedCinematicFormat = cinematicFormat
                        if #available(iOS 26.0, *), let input = self.videoInput,
                           input.isCinematicVideoCaptureSupported {
                            self.enableCinematicCapture(on: input)
                        }
                    } catch {
                        self.publishError("Failed to set cinematic format: \(error.localizedDescription)")
                        appliedMode = .standard
                        self.disableCinematicCapture()
                    }
                } else {
                    self.publishError("No cinematic format available on this device.")
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
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.onFormatApplied?(applied)
                }
            }
        }
    }

    /// Queries the device's full capabilities including cinematic mode support.
    /// Returns mode-specific format availability for proper UI validation.
    func queryDeviceCapabilities() -> DeviceCapabilities {
        // Standard capabilities come from the wide-angle camera.
        let wideAngle = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? videoDevice

        // Scan ALL front-facing cameras for CINE formats — different devices carry CINE
        // on different hardware generations (TrueDepth on iPhone 13, UltraWide on iPhone 17 Pro).
        let frontDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: allVideoDeviceTypes(),
            mediaType: .video,
            position: .front
        )

        // HD/4K threshold: midpoint between 1920x1080 (2.1MP) and 3840x2160 (8.3MP).
        let hdThreshold: Int64 = 5_184_000
        let hdTarget: Int64 = 1920 * 1080
        let k4Target: Int64 = 3840 * 2160

        var hasHDCine = false
        var has4KCine = false
        var cinematicFrameRates = Set<VideoFrameRate>()
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

                if pixels <= hdThreshold { hasHDCine = true } else { has4KCine = true }

                for range in fmt.videoSupportedFrameRateRanges {
                    for rate in VideoFrameRate.allCases {
                        if Double(rate.rawValue) >= range.minFrameRate &&
                           Double(rate.rawValue) <= range.maxFrameRate {
                            cinematicFrameRates.insert(rate)
                        }
                    }
                }
            }
        }

        // If there are CINE formats but none fit the threshold cleanly (e.g. all large),
        // fall back to treating the smallest as HD.
        if supportsCinematic && !hasHDCine && !has4KCine { hasHDCine = true }

        var cinematicResolutions: [VideoResolution] = []
        if hasHDCine { cinematicResolutions.append(.hd1080p) }
        if has4KCine { cinematicResolutions.append(.uhd4K) }

        Log.camera.info("All-front CINE scan: HD=\(hasHDCine, privacy: .public) 4K=\(has4KCine, privacy: .public) FPS=\(cinematicFrameRates.map(\.rawValue).sorted(), privacy: .public)")
        _ = hdTarget; _ = k4Target  // suppress unused warnings

        guard let device = wideAngle else {
            Log.camera.warning("No wide-angle device available for capability query")
            return DeviceCapabilities(
                supportsCinematicMode: supportsCinematic,
                standardResolutions: [.hd1080p],
                standardFrameRates: [.fps30],
                cinematicResolutions: cinematicResolutions.isEmpty ? [.hd1080p] : cinematicResolutions,
                cinematicFrameRates: cinematicFrameRates.isEmpty ? [.fps24, .fps30] : cinematicFrameRates.sorted { $0.rawValue < $1.rawValue }
            )
        }

        Log.camera.info("Capabilities: wideAngle=\(device.localizedName, privacy: .public) | Cinematic=\(supportsCinematic, privacy: .public)")

        // Standard mode: resolution (session-preset based).
        var standardResolutions: [VideoResolution] = [.hd1080p]
        if session.canSetSessionPreset(.hd4K3840x2160) {
            standardResolutions.append(.uhd4K)
        }

        // Standard mode: scan wide-angle formats for supported frame rates.
        var standardFrameRates = Set<VideoFrameRate>()
        for deviceFormat in device.formats {
            for range in deviceFormat.videoSupportedFrameRateRanges {
                for rate in VideoFrameRate.allCases {
                    if Double(rate.rawValue) >= range.minFrameRate &&
                       Double(rate.rawValue) <= range.maxFrameRate {
                        standardFrameRates.insert(rate)
                    }
                }
            }
        }

        let capabilities = DeviceCapabilities(
            supportsCinematicMode: supportsCinematic,
            standardResolutions: standardResolutions,
            standardFrameRates: standardFrameRates.sorted { $0.rawValue < $1.rawValue },
            cinematicResolutions: cinematicResolutions.isEmpty && supportsCinematic ? [.hd1080p] : cinematicResolutions.sorted { $0.rawValue < $1.rawValue },
            cinematicFrameRates: cinematicFrameRates.isEmpty && supportsCinematic
                ? [.fps24, .fps30]
                : cinematicFrameRates.sorted { $0.rawValue < $1.rawValue }
        )

        Log.camera.info("Capabilities: Cinematic=\(supportsCinematic, privacy: .public) StdRes=\(standardResolutions.map(\.rawValue), privacy: .public) StdFPS=\(capabilities.standardFrameRates.map(\.rawValue), privacy: .public) CineRes=\(capabilities.cinematicResolutions.map(\.rawValue), privacy: .public) CineFPS=\(capabilities.cinematicFrameRates.map(\.rawValue), privacy: .public)")

        return capabilities
    }

    /// Finds a CINE-capable format on the given device matching the requested resolution and frame rate.
    /// Only searches the device's own formats — no companion-device lookup.
    /// Finds the best CINE-capable format on the given device for the requested resolution and fps.
    /// Uses a fixed pixel threshold (5.2MP) to split HD vs 4K size classes, then picks
    /// the format closest to the standard target pixels (1920x1080 or 3840x2160) within that class.
    private func findCinematicFormat(
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
    private func logAllCameraFormats() {
        let deviceTypes = allVideoDeviceTypes()
        
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
    private func allVideoDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInTrueDepthCamera
        ]
        if #available(iOS 13.0, *) {
            types.append(contentsOf: [
                .builtInUltraWideCamera,
                .builtInTelephotoCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera
            ])
        }
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
    private func enableCinematicCapture(on input: AVCaptureDeviceInput) {
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

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onCinematicApertureAvailable?(minAp, maxAp, defAp)
            }
        }
    }

    /// Disables cinematic capture on the stored input and signals the UI to hide the aperture control.
    private func disableCinematicCapture() {
        if #available(iOS 26.0, *) {
            if let input = videoInput, input.isCinematicVideoCaptureSupported {
                input.isCinematicVideoCaptureEnabled = false
                Log.camera.info("Cinematic video capture DISABLED")
            }
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // (0, 0, 0) signals ViewModel to clear the aperture panel.
                self.onCinematicApertureAvailable?(0, 0, 0)
            }
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
            Log.camera.notice("FPS \(rate.rawValue, privacy: .public) unsupported by active format, falling back to \(targetRate.rawValue, privacy: .public)")
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
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onRecordingStateChanged?(isRecording)
            }
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onError?(message)
            }
        }
    }

    private func publishSessionRunningState(_ isRunning: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onSessionRunningStateChanged?(isRunning)
            }
        }
    }

    private func publishLockOutcome(_ outcome: FocusExposureLockOutcome, completion: (@MainActor @Sendable (FocusExposureLockOutcome) -> Void)?) {
        guard let completion else { return }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                completion(outcome)
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

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

// MARK: - Float Extension

extension Float {
    /// Returns the value clamped to the given range.
    func clamped(to range: ClosedRange<Float>) -> Float {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
