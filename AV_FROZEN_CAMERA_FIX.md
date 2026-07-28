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

Add three `NotificationCenter` observers in `CameraService` at the end of `configureSession`, following the same pattern Apple uses in AVCam:

**`AVCaptureSession.wasInterruptedNotification`**

- Set a `wasInterrupted` flag.
- Log the interruption reason for diagnostics.

**`AVCaptureSession.interruptionEndedNotification`**

- If `wasInterrupted` is true and `isSessionConfigured` is true: call `startRunning()` on `sessionQueue`.
- Clear `wasInterrupted`.

**`AVCaptureSession.runtimeErrorNotification`**

- Read the error from `userInfo[AVCaptureSessionErrorKey]`.
- If the error code is `.mediaServicesWereReset`: call `startRunning()` on `sessionQueue` to attempt recovery.
- Otherwise: publish the error through the existing `publishError()` path.

### Optional (symptom mitigation only)

Increasing `Timing.keyboardDismissDelay` in `ComposeScriptSheet` beyond 350ms gives the Speech engine more time to release `AVAudioSession` before the camera restarts. This is not a reliable fix on its own because the release timing is non-deterministic — use the notifications above instead.

---

## Files to Change

- `PromptCam/Services/CameraService.swift`
  - Add `wasInterrupted: Bool` flag
  - Add three `NotificationCenter.default.addObserver` calls at the end of `configureSession`
  - Add corresponding handler methods: `sessionWasInterrupted(_:)`, `sessionInterruptionEnded(_:)`, `sessionRuntimeError(_:)`
  - Remove observers in `deinit` (or use token-based observation to auto-remove)
