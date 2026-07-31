# Frozen Camera Preview After Voice Dictation + Save

## Bug Description

When a user opens the Script (Compose) view, uses voice dictation to write a script, taps Save, and returns to the main camera UI — the camera preview is frozen. The rest of the app (buttons, UI, script display) works normally. Closing and reopening the app restores the preview and the script is preserved.

---

## Execution Path Trace

### 1. Compose sheet opens

`fullScreenCover(isPresented: $viewModel.showComposeSheet)` covers `CameraView`.
SwiftUI calls `CameraView.onDisappear` → `viewModel.onDisappear()` → `cameraService.stopSession()`.
`session.stopRunning()` is queued on `sessionQueue` and executes. `session.isRunning` becomes `false`.

### 2. User dictates

iOS Speech Recognition (keyboard dictation) activates and takes exclusive control of `AVAudioSession`.
The capture session is already stopped at this point — no immediate conflict.

### 3. User taps Save

`dismissAndRun { onSave(...) }` in `ComposeScriptSheet` fires:

- Sets `isEditorFocused = false` → keyboard dismissal animation begins
- Waits `Timing.keyboardDismissDelay` (350ms)
- After 350ms: calls `onSave(text)` → `viewModel.updateScriptText(text)` + `viewModel.dismissComposeSheet()` → `showComposeSheet = false`

### 4. Sheet dismisses

`CameraView.onAppear` fires → `viewModel.onAppear()`:

- `configureSession()` → **no-op**: guarded by `guard !self.isSessionConfigured else { return }`. No re-wiring of inputs or outputs occurs.
- `startSession()` → checks `session.isRunning` (false) → calls `session.startRunning()`

### 5. The race condition

`session.startRunning()` must internally reactivate `AVAudioSession` in `.videoRecording` mode to resume the audio capture input that is part of the session.

iOS Speech Recognition was dismissed only ~350ms earlier. The Speech engine may still be in the process of releasing its `AVAudioSession` hold at this moment. `startRunning()` returns without throwing an error, but the capture session enters a degraded or interrupted state immediately after starting. The `AVPreviewLayer` renders the last captured frame (frozen) because no new video frames are delivered. `session.isRunning` reads `true`, which is why the rest of the app appears functional.

---

## The Structural Gap

`CameraService` does **not** observe any of the three `AVCaptureSession` runtime notifications that Apple's own AVCam sample code treats as required:

| Notification                                     | What it signals                                             | Current handling |
| ------------------------------------------------ | ----------------------------------------------------------- | ---------------- |
| `AVCaptureSession.wasInterruptedNotification`    | Session froze — audio conflict, phone call, dictation, etc. | **Not observed** |
| `AVCaptureSession.interruptionEndedNotification` | Safe to call `startRunning()` again                         | **Not observed** |
| `AVCaptureSession.runtimeErrorNotification`      | Session hit an internal error mid-run                       | **Not observed** |

Without these, any session freeze is silently dropped. There is no recovery path. The app has no way to know the session was interrupted and no mechanism to restart it.

---

## Why Other Flows Don't Trigger This

Returning from the recordings player, camera settings sheet, or format sheet does not involve any `AVAudioSession` competition. `startRunning()` succeeds cleanly on `onAppear` in those cases.

Voice dictation is the only flow that leaves `AVAudioSession` in a transitioning state at the exact moment the camera tries to restart — making it the unique trigger for this bug.

---

## Fix Direction

### Required (permanent fix)

Add three `NotificationCenter` observers in `CameraService` at the end of `configureSession`, following the same pattern Apple uses in AVCam.

---

### 1. Threading Model

`CameraService` documents its `@unchecked Sendable` conformance by requiring all mutable state to be mutated exclusively from `sessionQueue`. The new notification handlers must respect this invariant.

**Rules:**

- The new `wasInterrupted: Bool` flag lives on the instance but is **read and written only from `sessionQueue`**.
- Notification handlers are registered with the selector-based API (`addObserver(_:selector:name:object:)`), which delivers callbacks on the posting thread. Every handler's first line must be `sessionQueue.async { ... }` so all state access is serialized.
- The existing `isSessionConfigured` and `session.isRunning` reads inside the handlers are already `sessionQueue`-safe under this rule.

---

### 2. Interruption Reason Handling

Handlers must read `userInfo[AVCaptureSessionInterruptionReasonKey]` and branch on `AVCaptureSession.InterruptionReason`. Not every reason warrants an auto-restart.

| Reason                                              | Trigger                                  | Action                                                                         |
| --------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------ |
| `audioDeviceInUseByAnotherClient`                   | Dictation, Siri, phone call, VoIP        | Set `wasInterrupted = true`. Wait for `.interruptionEnded`. **Primary case.**  |
| `videoDeviceInUseByAnotherClient`                   | Another camera app took the video device | Set `wasInterrupted = true`. Wait for `.interruptionEnded`.                    |
| `videoDeviceNotAvailableInBackground`               | App was backgrounded                     | Do nothing — scene phase handling owns this.                                   |
| `videoDeviceNotAvailableWithMultipleForegroundApps` | iPad Slide Over / Split View             | Do nothing — user-initiated multitasking.                                      |
| `videoDeviceNotAvailableDueToSystemPressure`        | Thermal / performance throttle           | Set `wasInterrupted = true`, publish a user-facing warning via `publishError`. |
| unknown / future                                    | —                                        | Log at `.info`. Set `wasInterrupted = true` defensively.                       |

For the dictation-freeze bug, `audioDeviceInUseByAnotherClient` is the reason iOS posts when Speech Recognition acquires `AVAudioSession`.

---

### 3. `interruptionEnded` Restart Guards

Restarting is only safe when all of the following hold, evaluated on `sessionQueue`:

1. `wasInterrupted == true` (we set it, so we own the restart).
2. `isSessionConfigured == true`.
3. `!session.isRunning` (defensive — avoids double-start).
4. **The app is in the foreground.** Read `UIApplication.shared.applicationState == .active` on the main thread and hop back to `sessionQueue` before calling `startRunning()`.
5. **The view is on-screen.** Introduce a new `isForegroundActive: Bool` published from `CameraView` via a lifecycle callback on the view model, defaulting to `false` and set to `true` in `viewModel.onAppear` and `false` in `viewModel.onDisappear`. The handler must gate the restart on this flag.

Guards (4) and (5) prevent racing `onDisappear`'s `stopSession()` when the user dismisses the app or navigates away mid-interruption.

After a successful restart, clear `wasInterrupted = false` on `sessionQueue`.

---

### 4. Observer Lifecycle

**Registration style:** selector-based on `self` — `addObserver(_:selector:name:object:)` — because `CameraService` inherits from `NSObject` and this style survives Swift 6 sendability checks with the least ceremony.

**Registration timing:** at the very end of `configureSession`'s success path, after `isSessionConfigured = true`. Registering earlier risks receiving notifications for a partially wired session.

**Deregistration:** the very first statement of `deinit` must be `NotificationCenter.default.removeObserver(self)`. This runs synchronously on whatever thread is releasing the instance and completes before the existing `sessionQueue.async { session.stopRunning() ... }` block is scheduled. Removing observers via a block dispatched to `sessionQueue` would be too late — the notification center could deliver a callback to a partially-deallocated instance.

**Object filter:** pass `object: session` on every `addObserver` call so we only receive notifications for our own capture session, not others in the process.

---

### 5. Runtime Error Handling

Handler behavior branches on `AVError.Code`:

| Code                      | Action                                                                                                                                                                                                                                         |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.mediaServicesWereReset` | Set `isSessionConfigured = false`, tear down inputs/outputs on `sessionQueue`, call `configureSession(format:)` with the last-known format, then `startSession()`. `startRunning()` alone is insufficient because all outputs are invalidated. |
| `.sessionWasInterrupted`  | Defensive: treat as an interruption event even though `.wasInterrupted` should have fired instead. Log and set `wasInterrupted = true`.                                                                                                        |
| any other                 | `publishError(.sessionRuntimeError(error.localizedDescription))`. Do not attempt recovery.                                                                                                                                                     |

The last-known `RecordingFormat` must be cached on `CameraService` (new `private var lastConfiguredFormat: RecordingFormat?`) so media-services-reset recovery can replay it. Set it at the end of the successful `configureSession` path.

---

### Optional (symptom mitigation only)

Increasing `Timing.keyboardDismissDelay` in `ComposeScriptSheet` beyond 350ms gives the Speech engine more time to release `AVAudioSession` before the camera restarts. **Do not adopt this** once the notifications are wired — masking the real fix with delay is fragile and hides regressions.

---

## Verification Plan

### Repro Steps (must reproduce before fix, must not reproduce after)

1. Launch app on device, land on camera view.
2. Tap "Compose Script" to open the sheet.
3. Tap the mic key on the iOS keyboard and dictate 3–5 words.
4. Tap the Save toolbar button.
5. Observe the camera preview within 1 second of the sheet dismissing.

**Pass:** preview shows live video within 1s.
**Fail:** preview shows a frozen frame; only closing and reopening the app restores it.

### Regression Checks

- **Phone call during recording:** receive a call, decline it — recording should resume when interruption ends.
- **Siri activation:** invoke Siri from the camera view, dismiss — preview resumes.
- **Control Center audio:** start music from Control Center, dismiss — preview resumes.
- **App backgrounding mid-record:** background the app while recording, foreground — recording stops cleanly, preview resumes.
- **iPad Slide Over (if supported later):** should NOT auto-restart when Slide Over grabs the camera.

### Log Assertions

During repro, `Log.camera` must show:

- `AVCaptureSession interrupted: reason=audioDeviceInUseByAnotherClient`
- `AVCaptureSession interruption ended — restarting`
- `AVCaptureSession startRunning succeeded (post-interruption)`

Absence of these lines during a repro indicates the observers are not wired or the reason was misclassified.

---

## Files to Change

### `PromptCam/Services/CameraService.swift`

- Add `private var wasInterrupted: Bool = false` (sessionQueue-only)
- Add `private var lastConfiguredFormat: RecordingFormat?` (sessionQueue-only)
- Add three `NotificationCenter.default.addObserver` calls at the end of `configureSession`'s success branch, filtered by `object: session`
- Add handler methods: `@objc func sessionWasInterrupted(_:)`, `@objc func sessionInterruptionEnded(_:)`, `@objc func sessionRuntimeError(_:)`
- Add `NotificationCenter.default.removeObserver(self)` as the first line of `deinit`
- Cache `lastConfiguredFormat = format` at the end of the `configureSession` success path
- Add a `.sessionRuntimeError(String)` case to `CameraError` (see below)

### `PromptCam/Services/CameraError.swift`

- Add `case sessionRuntimeError(String)` with a user-friendly `localizedDescription`

### `PromptCam/ViewModels/CameraViewModel.swift`

- Add `private(set) var isForegroundActive: Bool = false`
- Set `true` in `onAppear` before `startSession()`, `false` in `onDisappear` after `stopSession()`
- Expose a read closure to `CameraService` at init (mirrors the existing `audioMeter.isRecording` pattern) so the interruption-ended handler can consult it from `sessionQueue`

### `PromptCamTests/CameraServiceInterruptionTests.swift` (new)

Purpose: verify the observer wiring and reason-branching logic without a real `AVCaptureSession`. Uses an injected `NotificationCenter` so tests can post synthetic notifications.

Required tests:

1. **`test_wasInterrupted_audioReason_setsFlagAndDoesNotRestart`**
   Post `.wasInterruptedNotification` with `audioDeviceInUseByAnotherClient`. Assert `wasInterrupted == true` and that `startSession` was NOT called.

2. **`test_wasInterrupted_backgroundReason_isIgnored`**
   Post with `videoDeviceNotAvailableInBackground`. Assert `wasInterrupted == false` and no restart attempted.

3. **`test_interruptionEnded_afterAudio_restartsWhenForegroundActive`**
   Set `wasInterrupted = true` and stub `isForegroundActive = true`. Post `.interruptionEndedNotification`. Assert `startSession` called and `wasInterrupted` cleared.

4. **`test_interruptionEnded_skipsRestart_whenNotForegroundActive`**
   Same as above but `isForegroundActive = false`. Assert `startSession` NOT called and `wasInterrupted` remains `true`.

5. **`test_interruptionEnded_skipsRestart_whenSessionNotConfigured`**
   `isSessionConfigured = false`. Post `.interruptionEndedNotification`. Assert no restart.

6. **`test_runtimeError_mediaServicesReset_reconfiguresAndRestarts`**
   Cache a `RecordingFormat`. Post `.runtimeErrorNotification` with `AVError(.mediaServicesWereReset)`. Assert `isSessionConfigured` was reset, `configureSession` was called with the cached format, and `startSession` was called.

7. **`test_runtimeError_unknownError_publishesError_noRestart`**
   Post with a generic `AVError(.unknown)`. Assert `onError` fired with `.sessionRuntimeError`, no restart attempted.

8. **`test_deinit_removesObservers`**
   Create a service, capture a weak reference, drop the strong reference, then post `.wasInterruptedNotification` on a live notification center. Assert no crash and the handler counter did not increment. Verifies `removeObserver(self)` runs before deallocation completes.

Reuse the `MockCameraService` scaffolding pattern already established in `CameraViewModelTests`. Inject a `NotificationCenter` (default parameter falls back to `.default` in production) into `CameraService.init` so the test suite can post to an isolated center.

### `PromptCam/Views/Sheets/ComposeScriptSheet.swift`

- **No changes.** Do not adjust `keyboardDismissDelay`.
