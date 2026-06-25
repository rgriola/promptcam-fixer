# Clean HDMI Output — PromptCam

## Goal

When a USB-C → HDMI adapter is connected, output a **clean camera feed + audio** to the external display while the iPhone continues showing the full app UI.

**Output contract (fixed):**
- ✅ Camera feed — full-screen, fill gravity
- ✅ Audio — routed automatically by `AVAudioSession` through the HDMI adapter
- ❌ No teleprompter text — ever
- ❌ No app UI, overlays, or indicators on the HDMI output
- ❌ No HDMI indicator shown on the iPhone UI

---

## How It Fits the Existing App

| Existing piece | Role in HDMI feature |
|---|---|
| `CameraService.session` (`AVCaptureSession`) | Single session — all video/audio flows from here. HDMI preview taps in with a second layer. |
| `CameraService.previewSession` | Already a public read-only accessor — HDMI window uses it directly. |
| `CameraViewModel.session` | Forwarded from `previewSession` — already passed to `CameraPreviewView` on iPhone. |
| `CameraPreviewView` / `PreviewView` | Uses `AVCaptureVideoPreviewLayer`. A second, gesture-free version is created for the HDMI window. |
| `PromptCamApp` / `WindowGroup` | Unchanged — a second `UIWindow` is managed imperatively by `ExternalDisplayService`. |

> [!IMPORTANT]
> `AVCaptureVideoPreviewLayer` supports **multiple instances per session**. Two preview layers can connect to the same running `AVCaptureSession` with no conflicts and no session restart.

> [!NOTE]
> **Audio is automatic.** When a USB-C → HDMI adapter is connected, iOS includes it as an `AVAudioSession` output route. The captured mic audio embeds in the HDMI signal with no additional code required.

---

## Proposed Changes

### New Service

#### [NEW] `Services/ExternalDisplayService.swift`

`ObservableObject` that owns the entire HDMI lifecycle:

- Observes `UIScreen.didConnectNotification` / `UIScreen.didDisconnectNotification`
- On connect: creates `ExternalDisplayWindow` on the new screen, attaches the preview layer
- On disconnect: tears down the window, releases the preview layer
- Holds a weak reference to the `AVCaptureSession` so it doesn't extend session lifetime

```swift
final class ExternalDisplayService: ObservableObject {
    @Published private(set) var isConnected: Bool = false
    func start(session: AVCaptureSession)   // call after session is running
    func stop()                             // call on app teardown
}
```

---

### New Views

#### [NEW] `Views/ExternalDisplay/CleanPreviewView.swift`

A stripped-down `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer`:
- Video gravity: `.resizeAspectFill` (fills the HDMI display edge-to-edge)
- **No gesture recognizers** — tap-to-focus must not fire from the external screen
- No coordinators, no callbacks — purely display

#### [NEW] `Views/ExternalDisplay/CleanOutputView.swift`

The SwiftUI root view for the HDMI `UIWindow`:
- Black `Color.black.ignoresSafeArea()` background
- `CleanPreviewView` full-screen on top
- Nothing else

---

### New UIKit Helper

#### [NEW] `Views/ExternalDisplay/ExternalDisplayWindow.swift`

Factory / manager for the `UIWindow` on the external screen:
- Takes a `UIWindowScene` from the external `UIScreen`
- Hosts `UIHostingController<CleanOutputView>`
- Makes the window key and visible
- Retained by `ExternalDisplayService`; set to `nil` on disconnect to release

---

### Modified Files

#### [MODIFY] [CameraService.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/CameraService.swift)

Add one 3-line method:

```swift
/// Returns a new AVCaptureVideoPreviewLayer connected to the running session.
/// Safe to call while the session is active — no configuration block needed.
func makeExternalPreviewLayer() -> AVCaptureVideoPreviewLayer {
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    return layer
}
```

#### [MODIFY] [CameraViewModel.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/ViewModels/CameraViewModel.swift)

- Add `private let externalDisplayService = ExternalDisplayService()`
- After `cameraService.startSession()` succeeds, call `externalDisplayService.start(session: cameraService.previewSession)`
- In `deinit` / teardown, call `externalDisplayService.stop()`

No new published properties — the service runs silently.

---

## Implementation Order

1. `ExternalDisplayService` — screen detection, notification wiring, window lifecycle
2. `CleanPreviewView` — gesture-free `UIViewRepresentable`
3. `CleanOutputView` — black background + `CleanPreviewView` full-screen
4. `ExternalDisplayWindow` — `UIWindow` factory targeting external `UIWindowScene`
5. `CameraService.makeExternalPreviewLayer()` — 3-line addition
6. `CameraViewModel` — instantiate service, wire `start()` / `stop()`

---

## What Does NOT Change

- `AVCaptureSession` — no restart, no reconfiguration
- `CameraPreviewView` — iPhone preview unchanged
- `CameraView` — no layout changes
- `AudioMeterService` — unchanged
- All recording logic — recordings save to device normally
- `PromptCamApp.swift` — `WindowGroup` unchanged; second window is UIKit-managed

---

## Verification Plan

| Test | Expected result |
|---|---|
| Connect adapter → monitor | External display shows full-screen camera feed, black background |
| Disconnect adapter mid-session | iPhone continues normally, no crash |
| Tap focus on iPhone | HDMI feed updates (same session); no touch events on HDMI side |
| Record while HDMI connected | Recording saves to device normally |
| Switch Standard ↔ Cinematic | HDMI preview follows session (same layer) |
| Connect HDMI before app launch | Service picks up existing screen on `start()` |
| AirPlay to Apple TV | Same code path — AirPlay presents as a virtual `UIScreen` |
| No adapter connected | Zero performance impact — service observes but does nothing |
