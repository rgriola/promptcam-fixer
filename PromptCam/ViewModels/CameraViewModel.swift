// May 31, 2026 - 2:30am - GitHub Copilot (Claude Opus 4.7)
// June 13, 2026 - GitHub Copilot (Claude Sonnet 4.5) - Added recording timer with Combine
import AVFoundation
import Combine
import Photos
import SwiftUI

enum CameraSheetRoute: String, Identifiable, Sendable {
    case formatPanel
    case composeScript
    case settings
    case recordingsLibrary

    var id: String { rawValue }
}

enum CameraMode: Equatable, Sendable {
    case camera
    case compose
}

enum CameraLockStatus: Equatable, Sendable {
    case auto
    case aeAfLocked
    case aeLocked
    case afLocked
    case unsupported

    var isLocked: Bool {
        switch self {
        case .aeAfLocked, .aeLocked, .afLocked:
            return true
        case .auto, .unsupported:
            return false
        }
    }

    var text: String {
        switch self {
        case .auto:
            return "AUTO"
        case .aeAfLocked:
            return "AE/AF LOCK"
        case .aeLocked:
            return "AE LOCK"
        case .afLocked:
            return "AF LOCK"
        case .unsupported:
            return "LOCK UNAVAILABLE"
        }
    }

    /// Two-part display label for stacked badge layout.
    /// `top` is the sensor abbreviation; `bottom` is the state word (or `nil` for single-line).
    var displayParts: (top: String, bottom: String?) {
        switch self {
        case .auto:          return ("AUTO",  nil)
        case .aeAfLocked:    return ("AE/AF", "Lock")
        case .aeLocked:      return ("AE",    "Lock")
        case .afLocked:      return ("AF",    "Lock")
        case .unsupported:   return ("LOCK",  "UNAVAIL")
        }
    }
}

/// Central state owner for the camera screen.
///
/// **@MainActor**: All published properties drive SwiftUI views, so the entire
/// class is main-actor-isolated. Camera hardware calls go through `CameraService`
/// which runs them on its own serial queue.
///
/// **Modal queue pattern**: SwiftUI allows only one `.sheet` presenter at a time.
/// If the user triggers a second modal while one is active, the request is queued
/// in `queuedSheet` (or `queuedPhotoPicker`). When the active modal dismisses,
/// `presentQueuedModalIfNeeded()` dequeues the next one. This prevents the
/// "sheet not presented" bug that occurs with rapid modal switching.
///
/// **Callback binding**: `bindCallbacks()` connects `CameraService` closures to
/// observable properties at init time, keeping the service layer protocol-free.
@MainActor
@Observable
final class CameraViewModel {
    var config = TeleprompterConfig.default
    var isRecording = false
    var isScrolling = false
    /// Recording duration in seconds, updated every 0.1s while recording.
    var recordingDuration: TimeInterval = 0

    var cameraError: CameraError?
    var lockStatus: CameraLockStatus = .auto
    var isCameraReady = false
    var activeSheet: CameraSheetRoute?
    /// Compose sheet is presented as a fullScreenCover to prevent
    /// iOS sheet presentation from rescaling the camera preview.
    var showComposeSheet = false
    var cameraMode: CameraMode = .camera
    /// Warning banner for format panel locked during recording.
    var showFormatLockedWarning = false
    /// Bumped to signal the overlay to reset position (zero manualOffset).
    var teleprompterResetToken: Int = 0
    /// Current recording format (resolution + FPS). Persisted across launches.
    var recordingFormat: RecordingFormat
    /// Device capabilities (mode support, resolution/fps per mode).
    var deviceCapabilities: DeviceCapabilities = DeviceCapabilities(
        supportsCinematicMode: false,
        standardFormats: [RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .standard)],
        cinematicFormats: []
    )
    /// Aperture range reported by the active cinematic format (iOS 26+ only).
    /// Nil when cinematic mode is inactive or device/OS does not support it.
    var cinematicApertureRange: ClosedRange<Float>? = nil
    /// Current simulated aperture value shown in the aperture slider.
    var cinematicSimulatedAperture: Float = 2.0

    // MARK: - Audio Metering

    /// Current average audio input level Ch1 (0.0–1.0).
    var audioLevel: Float = 0
    /// Current peak-hold audio level Ch1 (0.0–1.0).
    var audioPeak: Float = 0
    /// Current average audio level Ch2 (0.0–1.0). Non-zero only when a stereo input is active.
    var audioLevel2: Float = 0
    /// Current peak-hold audio level Ch2 (0.0–1.0). Non-zero only when a stereo input is active.
    var audioPeak2: Float = 0
    /// True when the active audio input is a stereo device (e.g. dual-channel wireless receiver).
    var isStereoInput: Bool = false
    /// Whether an external microphone is connected.
    var isExternalMic: Bool = false
    /// Marketing name of the external mic, if available.
    var externalMicName: String?
    /// Whether hardware gain control is available on this device.
    var isGainAvailable: Bool = false
    /// Current audio input gain (0.0–1.0). Only functional when `isGainAvailable`.
    var audioGain: Float = 0.5
    /// Available audio input sources (built-in mic, USB, BT, etc.).
    var availableAudioInputs: [AVAudioSessionPortDescription] = []
    /// Name of the currently active audio input.
    var activeAudioInputName: String?
    /// When true, present the audio source picker to the user.
    var showAudioSourcePicker: Bool = false
    /// Warning banner shown when the audio route changes during recording
    /// (e.g. external mic disconnects mid-take). Auto-dismisses.
    var showAudioRouteChangedWarning: Bool = false
    /// Body text of the audio-route warning banner. Updated alongside
    /// `showAudioRouteChangedWarning`.
    var audioRouteChangedMessage: String = ""
    /// Warning banner shown when the silence watchdog detects sustained
    /// dead audio from an external mic (flaky cable, hardware mute, etc.).
    var showAudioSilenceWarning: Bool = false
    /// Source-name pill shown briefly beside the VU meter when the route
    /// changes. Cleared after a short delay.
    var audioSourceHint: String? = nil
    @ObservationIgnored private var audioSourceHintTask: Task<Void, Never>?

    // MARK: - Timer State
    
    @ObservationIgnored private var timerCancellable: AnyCancellable?
    @ObservationIgnored private var recordingStartDate: Date?
    
    // MARK: - Modal Queue State
    // See class-level doc for explanation of the queue pattern.

    @ObservationIgnored private var queuedSheet: CameraSheetRoute?
    @ObservationIgnored private var lastPresentedSheet: CameraSheetRoute?

    // MARK: - Direct Player State

    /// The most recently recorded video, pre-fetched so the player opens immediately.
    var latestRecording: Recording?
    /// Resolved URL for `latestRecording` — ready before the player opens.
    var latestVideoURL: URL?
    /// First 8 recordings for the carousel, pre-warmed by PHCachingImageManager.
    var recentRecordings: [Recording] = []
    /// Controls direct player sheet presentation.
    var showDirectPlayer = false

    @ObservationIgnored private let recordingsService = RecordingsService()

    // MARK: - Style Persistence Keys
    private enum StyleKey {
        static let fontSize   = "tp.fontSize"
        static let speed      = "tp.speed"
        static let textColor  = "tp.textColor"
        static let bgOpacity  = "tp.bgOpacity"
        static let alignment  = "tp.alignment"
        static let scriptText = "tp.scriptText"
    }

    let cameraService: CameraServiceProtocol
    private let permissionService: PermissionService
    @ObservationIgnored private var audioMeterService: AudioMeterService?
    /// Refreshes the carousel whenever the Photo Library changes (own saves,
    /// Photos.app deletes, iCloud sync). Started in onAppear, stopped in
    /// onDisappear. Complements onRecordingSavedToLibrary from CameraService.
    @ObservationIgnored private let photoLibraryMonitor = PhotoLibraryChangeMonitor()



    init(
        cameraService: CameraServiceProtocol = CameraService(),
        permissionService: PermissionService = PermissionService()
    ) {
        self.cameraService = cameraService
        self.permissionService = permissionService
        self.recordingFormat = RecordingFormat.loadSaved()
        loadStylePreferences()
        bindCallbacks()
    }

    var session: AVCaptureSession { cameraService.previewSession }

    func onAppear() {
        isCameraReady = false
        // Permissions are already granted by the onboarding page.
        cameraService.configureSession(format: recordingFormat)
        cameraService.startSession()
        // Wire external-display service so HDMI/AirPlay gets a clean feed.
        ExternalDisplayService.shared.configure(session: cameraService.previewSession)
        // Observe photo-library changes so the carousel refreshes on external
        // deletes, iCloud sync, etc. Debounced to coalesce bursts.
        photoLibraryMonitor.start { [weak self] in
            self?.refreshLatestRecording()
        }
        // Device capabilities are received via onDeviceCapabilitiesQueried callback
        // after configureSession completes on the session queue.
        // Audio metering attaches in onSessionRunningStateChanged callback.
        Task { await prefetchLatestRecording() }
    }

    func onDisappear() {
        stopTimer()
        audioMeterService?.stopMetering()
        audioMeterService?.stopMonitoringRoute()
        cameraService.stopSession()
        photoLibraryMonitor.stop()
        isCameraReady = false
    }

    func toggleRecording() {
        guard isCameraReady else { return }

        if isRecording {
            stopTimer()
            cameraService.stopRecording()
            Log.viewmodel.info("toggleRecording -> stopped")
        } else {
            startTimer()
            cameraService.startRecording()
            Log.viewmodel.info("toggleRecording -> started")
        }
    }

    func toggleScrolling() {
        isScrolling.toggle()
        Log.viewmodel.debug("toggleScrolling -> \(self.isScrolling, privacy: .public)")
    }

    func openPhotoLibrary() {
        guard !isRecording else { return }
        openDirectPlayer()
    }

    /// Opens the direct player on the most recent recording.
    /// If the latest recording isn't ready yet, falls back to the library sheet.
    func openDirectPlayer() {
        guard !isRecording else { return }
        if latestRecording != nil {
            showDirectPlayer = true
        } else {
            // Fallback: no recording exists yet
            presentSheet(.recordingsLibrary)
        }
    }

    /// Fetches the latest recording and pre-resolves its URL so the player
    /// opens without delay. Loads ALL recordings for the carousel — Recording
    /// objects are lightweight PHAsset wrappers (~100 bytes each). Only the
    /// first window of thumbnails is pre-warmed; the rest load on demand as
    /// the user swipes.
    func prefetchLatestRecording() async {
        let latest = recordingsService.fetchLatestRecording()
        latestRecording = latest

        // Resolve URL in background so it's ready when player opens.
        if let latest {
            latestVideoURL = await recordingsService.resolveURL(for: latest)
        }

        // Fetch all recordings — no limit. PHAsset references are tiny.
        let all = await recordingsService.fetchAllRecordings()
        recentRecordings = all

        // Pre-warm thumbnails for the first visible window only.
        let warmIDs = all.prefix(8).map(\.id)
        if !warmIDs.isEmpty {
            let carouselSize = CGSize(width: 144, height: 144)
            recordingsService.startCaching(ids: Array(warmIDs), targetSize: carouselSize)
        }
    }

    /// Pre-warms carousel thumbnails in a sliding window around the given
    /// recording. Call this when the user navigates to a new item so adjacent
    /// thumbnails are ready before they scroll into view.
    func warmCarouselCache(around recording: Recording, windowSize: Int = 4) {
        guard let index = recentRecordings.firstIndex(where: { $0.id == recording.id }) else { return }
        let lo = max(0, index - windowSize)
        let hi = min(recentRecordings.count - 1, index + windowSize)
        let ids = recentRecordings[lo...hi].map(\.id)
        recordingsService.startCaching(ids: ids, targetSize: CGSize(width: 144, height: 144))
    }

    /// Call after a recording finishes saving to refresh the player state.
    func refreshLatestRecording() {
        Task { await prefetchLatestRecording() }
    }

    

    func openCompose() {
        guard !isRecording else { return }
        cameraMode = .compose
        showComposeSheet = true
    }

    func dismissComposeSheet() {
        showComposeSheet = false
        cameraMode = .camera
    }

    func openSettings() {
        guard !isRecording else { return }
        presentSheet(.settings)
    }



    func openFormatPanel() {
        // Gate: Cannot change format while recording
        guard !isRecording else {
            withAnimation(Theme.panelSpring) {
                showFormatLockedWarning = true
            }
            return
        }// Sheet to change format
        presentSheet(.formatPanel)
    }



    func dismissActiveSheet() {
        activeSheet = nil
    }

    func handleSheetStateChanged(_ newValue: CameraSheetRoute?) {
        guard newValue == nil else { return }

        if lastPresentedSheet == .composeScript {
            cameraMode = .camera
        }

        lastPresentedSheet = nil
        presentQueuedModalIfNeeded()
    }



    func updateScriptText(_ text: String) {
        Log.viewmodel.debug("updateScriptText len=\(text.count, privacy: .public)")
        config.text = text
        saveStylePreferences()
    }

    /// Applies and clamps new style settings, then persists them.
    func updateTeleprompterStyle(_ updated: TeleprompterConfig) {
        // Preserve the current script text — only style fields change here.
        var next = updated.clamped
        next.text = config.text
        config = next
        saveStylePreferences()
        Log.viewmodel.debug("updateTeleprompterStyle fontSize=\(Int(self.config.fontSize), privacy: .public) speed=\(Int(self.config.speedPointsPerSecond), privacy: .public) color=\(self.config.textColor.rawValue, privacy: .public) bgOpacity=\(self.config.backgroundOpacity, privacy: .public)")
    }

    /// Cycles to the next text alignment option.
    @MainActor
    func cycleTextAlignment() {
        config.textAlignment = config.textAlignment.next
        saveStylePreferences()
        print("Text alignment cycled to: \(config.textAlignment.rawValue)")
    }

    // MARK: - Style Persistence

    private func saveStylePreferences() {
        let ud = UserDefaults.standard
        ud.set(config.fontSize,                   forKey: StyleKey.fontSize)
        ud.set(config.speedPointsPerSecond,        forKey: StyleKey.speed)
        ud.set(config.textColor.rawValue,          forKey: StyleKey.textColor)
        ud.set(config.backgroundOpacity,           forKey: StyleKey.bgOpacity)
        ud.set(config.textAlignment.rawValue,      forKey: StyleKey.alignment)
        // Only persist the script when it differs from the default placeholder
        // so a fresh install still shows the onboarding hint text.
        if config.text != TeleprompterConfig.default.text {
            ud.set(config.text, forKey: StyleKey.scriptText)
        }
    }

    private func loadStylePreferences() {
        let ud = UserDefaults.standard
        // Only override defaults if a value has actually been saved previously.
        if ud.object(forKey: StyleKey.fontSize) != nil {
            config.fontSize            = ud.double(forKey: StyleKey.fontSize)
            config.speedPointsPerSecond = ud.double(forKey: StyleKey.speed)
            config.backgroundOpacity   = ud.double(forKey: StyleKey.bgOpacity)
            if let raw = ud.string(forKey: StyleKey.textColor),
               let color = TeleprompterTextColor(rawValue: raw) {
                config.textColor = color
            }
            if let raw = ud.string(forKey: StyleKey.alignment),
               let alignment = TeleprompterTextAlignment(rawValue: raw) {
                config.textAlignment = alignment
            }
            config = config.clamped
            // Restore the saved script. If no script has been saved yet (fresh
            // install or user cleared it), fall back to the default hint text.
            if let saved = ud.string(forKey: StyleKey.scriptText), !saved.isEmpty {
                config.text = saved
            } else {
                config.text = TeleprompterConfig.default.text
            }
            Log.viewmodel.debug("loadStylePreferences restored fontSize=\(Int(self.config.fontSize), privacy: .public) speed=\(Int(self.config.speedPointsPerSecond), privacy: .public) color=\(self.config.textColor.rawValue, privacy: .public) bgOpacity=\(self.config.backgroundOpacity, privacy: .public) scriptLen=\(self.config.text.count, privacy: .public)")
        }
    }

    /// Resets the teleprompter to its centered starting position.
    /// Pauses scrolling first so the reset is visible to the user.
    func resetTeleprompterPosition() {
        if isScrolling {
            isScrolling = false
            Log.viewmodel.debug("resetTeleprompterPosition paused scrolling")
        }
        teleprompterResetToken += 1
        Log.viewmodel.debug("resetTeleprompterPosition token=\(self.teleprompterResetToken, privacy: .public)")
    }

    private func presentSheet(_ route: CameraSheetRoute) {
        guard activeSheet == nil else {
            queuedSheet = route
            return
        }

        // .composeScript is routed through showComposeSheet / fullScreenCover
        // to prevent the camera preview from being rescaled.

        lastPresentedSheet = route
        activeSheet = route
    }

    private func presentQueuedModalIfNeeded() {
        guard activeSheet == nil, let route = queuedSheet else { return }
        queuedSheet = nil
        presentSheet(route)
    }

    func focus(at devicePoint: CGPoint) {
        cameraService.focus(at: devicePoint)
    }

    func lockFocusExposure(at devicePoint: CGPoint) {
        cameraService.lockFocusExposure(at: devicePoint) { [weak self] outcome in
            self?.lockStatus = CameraLockStatus(outcome: outcome)
        }
    }

    func unlockFocusExposure() {
        cameraService.unlockFocusExposure()
        lockStatus = .auto
    }

    func setSimulatedAperture(_ value: Float) {
        cinematicSimulatedAperture = value
        cameraService.setSimulatedAperture(value)
    }

    func adjustExposure(by delta: Float) {
        cameraService.adjustExposure(by: delta)
    }

    /// Sets exposure bias to an absolute value. Use for reset — avoids delta drift.
    func setExposure(to value: Float) {
        cameraService.setExposure(to: value)
    }
    
    // MARK: - Recording Timer
    
    /// Starts the recording timer using Combine. Computes duration from a start
    /// date rather than accumulating increments, avoiding floating-point drift.
    private func startTimer() {
        recordingDuration = 0
        recordingStartDate = Date()
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.recordingStartDate else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        Log.viewmodel.debug("Recording timer started")
    }
    
    /// Stops and resets the recording timer.
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        recordingStartDate = nil
        recordingDuration = 0
        Log.viewmodel.debug("Recording timer stopped")
    }

    // MARK: - Recording Format

    /// Applies a new recording format to the camera. No-op if recording.
    func updateRecordingFormat(_ format: RecordingFormat) {
        guard !isRecording else { return }
        Log.viewmodel.info("updateRecordingFormat res=\(format.resolution.rawValue, privacy: .public) fps=\(format.frameRate.rawValue, privacy: .public) mode=\(format.mode.rawValue, privacy: .public)")
        cameraService.applyFormat(format)
    }

    private func bindCallbacks() {
        cameraService.onRecordingStateChanged = { [weak self] isRecording in
            guard let self else { return }
            self.isRecording = isRecording
            // When recording stops the video is saved to the photo library.
            // Refresh the latest recording so the direct player is ready immediately.
            if !isRecording {
                self.refreshLatestRecording()
            }
        }

        // Fires the instant PhotoKit actually persists the new asset — closes
        // the race where onRecordingStateChanged fires before the save is done.
        cameraService.onRecordingSavedToLibrary = { [weak self] in
            self?.refreshLatestRecording()
        }

        cameraService.onSessionRunningStateChanged = { [weak self] isRunning in
            guard let self else { return }
            self.isCameraReady = isRunning
            // Attach audio metering once the session is fully configured
            // and running. Attaching earlier fails because the session
            // hasn't added its audio input yet.
            if isRunning && self.audioMeterService == nil {
                self.setupAudioMeter()
            }
        }

        cameraService.onFormatApplied = { [weak self] applied in
            guard let self else { return }
            self.recordingFormat = applied
            applied.save()
            Log.viewmodel.info("format applied res=\(applied.resolution.rawValue, privacy: .public) fps=\(applied.frameRate.rawValue, privacy: .public)")
        }

        cameraService.onDeviceCapabilitiesQueried = { [weak self] capabilities in
            guard let self else { return }
            self.deviceCapabilities = capabilities
            Log.viewmodel.info("device capabilities cine=\(capabilities.supportsCinematicMode, privacy: .public)")
            
            // Auto-adjust format if current selection isn't supported.
            if !capabilities.isSupported(self.recordingFormat) {
                let adjusted = capabilities.adjusted(self.recordingFormat)
                self.recordingFormat = adjusted
                adjusted.save()
                Log.viewmodel.notice("format auto-adjusted to res=\(adjusted.resolution.rawValue, privacy: .public) fps=\(adjusted.frameRate.rawValue, privacy: .public) mode=\(adjusted.mode.rawValue, privacy: .public)")
            }
        }

        cameraService.onCinematicApertureAvailable = { [weak self] minAp, maxAp, defAp in
            guard let self else { return }
            if minAp == 0 {
                self.cinematicApertureRange = nil
                Log.viewmodel.info("Cinematic aperture: unavailable")
            } else {
                // Clamp the lower bound to f/5.6 — the app intentionally avoids
                // very shallow DoF settings (f/1.9–f/4.5) which look unnatural
                // for teleprompter/presenter use. The hardware minimum is preserved
                // as the floor in case a future device reports a higher minimum.
                let appMin: Float = max(minAp, 5.6)
                self.cinematicApertureRange = appMin...maxAp
                self.cinematicSimulatedAperture = appMin   // default to f/5.6
                Log.viewmodel.info("Cinematic aperture range f/\(appMin, privacy: .public)–f/\(maxAp, privacy: .public) (hw min f/\(minAp, privacy: .public), default f/\(defAp, privacy: .public))")
            }
        }

        cameraService.onError = { [weak self] error in
            self?.cameraError = error
        }
    }

    // MARK: - Audio Meter

    private func setupAudioMeter() {
        let meter = AudioMeterService()

        meter.onLevelsUpdated = { [weak self] ch1Level, ch1Peak, ch2Level, ch2Peak in
            self?.audioLevel = ch1Level
            self?.audioPeak = ch1Peak
            self?.audioLevel2 = ch2Level ?? 0
            self?.audioPeak2 = ch2Peak ?? 0
            self?.isStereoInput = ch2Level != nil
        }

        meter.onRouteChanged = { [weak self] isExternal, name in
            guard let self else { return }

            // Snapshot old state BEFORE updating — `isExternalMic` is set
            // only in this callback so it's a reliable "previous" value.
            let wasExternalBefore = self.isExternalMic
            let previousName = self.activeAudioInputName
            let micChanged = name != previousName

            // Update state.
            self.isExternalMic = isExternal
            self.externalMicName = name
            self.activeAudioInputName = name

            // When the active mic changes (plug/unplug), surface UI feedback.
            // Skip on initial setup (previousName was nil).
            guard micChanged && self.audioMeterService != nil else { return }

            // Detect direction using the boolean flag, which is immune to
            // the onInputsAvailable race condition.
            let disconnected = wasExternalBefore && !isExternal   // external → built-in

            // Always show an inline source-name hint beside the VU meter.
            self.showSourceHint(name)

            if self.isRecording {
                // Mid-recording route change: do NOT swap the capture session
                // (would corrupt the .mov). Warn the user instead.
                if disconnected {
                    self.audioRouteChangedMessage = "⚠ External mic disconnected. Recording continues on iPhone mic."
                } else {
                    self.audioRouteChangedMessage = "Audio source changed during recording. Stop to apply new mic."
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.showAudioRouteChangedWarning = true
                }
            } else {
                // Not recording — auto-switch the capture session immediately.
                // This mirrors what happens when the user taps an input in the
                // picker; no picker confirmation step needed.
                self.cameraService.reconfigureAudioInput()

                if disconnected {
                    // Mic was unplugged: show a brief warning so the user
                    // knows recording would now use the built-in mic.
                    self.audioRouteChangedMessage = "External mic disconnected. Switched to iPhone mic."
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.showAudioRouteChangedWarning = true
                    }
                }
                // Source hint already shown above via showSourceHint(name).
                // Picker remains accessible by tapping the VU meter.
            }
        }

        meter.onInputsAvailable = { [weak self] inputs in
            guard let self else { return }
            self.availableAudioInputs = inputs
            // Note: activeAudioInputName is updated exclusively in
            // onRouteChanged to avoid a race condition where this
            // callback overwrites it before the route callback can
            // detect the change.
        }

        meter.onSilenceWatchdog = { [weak self] isSilent in
            guard let self else { return }
            if isSilent {
                // Only warn when an external mic is active — a quiet room
                // with the built-in mic is normal, not a hardware fault.
                guard self.isExternalMic else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.showAudioSilenceWarning = true
                }
                Log.camera.warning("AudioMeterService: silence watchdog fired — external mic may be disconnected or muted")
            } else {
                // Audio recovered — dismiss the warning.
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.showAudioSilenceWarning = false
                }
                Log.camera.debug("AudioMeterService: silence watchdog cleared — audio recovered")
            }
        }

        // Start audio engine tap on the microphone for real-time levels.
        // Runs independently of AVCaptureSession — no conflicts.
        meter.startMetering()
        meter.startMonitoringRoute()

        self.isGainAvailable = meter.isGainAvailable(for: cameraService.audioDevice)
        self.activeAudioInputName = meter.activeInput?.portName
        self.audioMeterService = meter
    }

    /// Opens the audio source picker, refreshing the available inputs list
    /// from `AVAudioSession` first.
    ///
    /// iOS can lag updating `availableInputs` after a route change
    /// notification. Re-reading here guarantees the list is current when
    /// the user actually sees the picker.
    func openAudioSourcePicker() {
        guard !isRecording else { return }
        availableAudioInputs = AVAudioSession.sharedInstance().availableInputs ?? []
        activeAudioInputName = audioMeterService?.activeInput?.portName
            ?? AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
        withAnimation(.easeOut(duration: 0.25)) {
            showAudioSourcePicker = true
        }
    }

    /// User-selected audio input from the source picker.
    func selectAudioInput(_ port: AVAudioSessionPortDescription?) {
        audioMeterService?.selectInput(port)
        activeAudioInputName = port?.portName ?? audioMeterService?.activeInput?.portName
        showAudioSourcePicker = false
        // Sync the capture session's audio input to match.
        cameraService.reconfigureAudioInput()
    }

    /// Adjusts the hardware microphone gain.
    func setAudioGain(_ value: Float) {
        audioGain = value
        audioMeterService?.setGain(value, on: cameraService.audioDevice)
    }

    /// Shows the inline source-name pill beside the VU meter and auto-clears
    /// it after a short delay. Successive calls reset the timer.
    private func showSourceHint(_ name: String?) {
        audioSourceHintTask?.cancel()
        audioSourceHint = name
        guard name != nil else { return }
        audioSourceHintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.audioSourceHint = nil
        }
    }
}

private extension CameraLockStatus {
    init(outcome: FocusExposureLockOutcome) {
        switch outcome {
        case .afAeLocked:
            self = .aeAfLocked
        case .aeLocked:
            self = .aeLocked
        case .afLocked:
            self = .afLocked
        case .unsupported:
            self = .unsupported
        }
    }
}
