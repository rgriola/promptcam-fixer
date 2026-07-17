// July 17, 2026 - GitHub Copilot - Extracted audio metering from CameraViewModel
import AVFoundation
import SwiftUI

/// Owns all audio-metering state and the `AudioMeterService` lifecycle for the
/// camera screen. Extracted from `CameraViewModel` so the coordinator stays
/// thin; the view reads levels/warnings through `viewModel.audioMeter`.
///
/// **@MainActor**: All observable properties drive SwiftUI views. Hardware
/// metering runs on `AudioMeterService`'s own engine; callbacks hop back to the
/// main actor before mutating state here.
///
/// **Dependencies**: needs `CameraServiceProtocol` (to reconfigure the capture
/// session's audio input and read the active `audioDevice`) and a live
/// `isRecording` provider so route-change handling can choose between warning
/// the user (mid-recording) and auto-switching (idle).
@MainActor
@Observable
final class AudioMeterViewModel {
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

    @ObservationIgnored private var audioMeterService: AudioMeterService?
    @ObservationIgnored private var audioSourceHintTask: Task<Void, Never>?
    @ObservationIgnored private let cameraService: CameraServiceProtocol
    /// Live provider for the recording flag, read at callback time so
    /// route-change handling reflects the current state. Set by the owning
    /// `CameraViewModel` after init (once `self` is fully initialized).
    @ObservationIgnored var isRecording: () -> Bool = { false }

    /// - Parameter cameraService: capture-session seam used to reconfigure
    ///   audio input and read the active `audioDevice`.
    init(cameraService: CameraServiceProtocol) {
        self.cameraService = cameraService
    }

    /// True once metering has been attached. Mirrors the previous
    /// `audioMeterService == nil` gate in the coordinator.
    var isActive: Bool { audioMeterService != nil }

    /// Attaches audio metering once the capture session is fully configured and
    /// running. Idempotent — safe to call on every running-state change.
    /// Attaching earlier fails because the session hasn't added its audio input yet.
    func setup() {
        guard audioMeterService == nil else { return }

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

            if self.isRecording() {
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

    /// Stops metering and route monitoring. Call from the screen's `onDisappear`.
    func stop() {
        audioMeterService?.stopMetering()
        audioMeterService?.stopMonitoringRoute()
    }

    /// Opens the audio source picker, refreshing the available inputs list
    /// from `AVAudioSession` first.
    ///
    /// iOS can lag updating `availableInputs` after a route change
    /// notification. Re-reading here guarantees the list is current when
    /// the user actually sees the picker.
    func openAudioSourcePicker() {
        guard !isRecording() else { return }
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
