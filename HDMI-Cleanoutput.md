# Clean HDMI Output — PromptCam

_Last updated: July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) — iOS 18+; audio monitoring deferred_

## Goal

When a USB-C → HDMI adapter (or AirPlay non-mirrored screen) is connected, output a **clean camera feed** to the external display while the iPhone continues showing the full app UI. Always on — no toggle, no UI indicator.

**Output contract:**

- ✅ Camera feed — full-screen, fill gravity
- ⚠️ Mic-audio monitoring on HDMI — **deferred** (see caveat below). Recording audio still writes to the file as always.
- ❌ No teleprompter text — ever
- ❌ No app UI, overlays, or indicators on the HDMI output
- ❌ No HDMI indicator shown on the iPhone UI

> [!WARNING]
> **iOS does not expose `AVCaptureAudioPreviewOutput` (macOS-only).** Live mic monitoring to the HDMI audio route on iOS requires `AVAudioEngine` with the input node routed to the mixer/output node, coordinated with the existing `AVCaptureSession` audio input. This is a non-trivial addition and is tracked as a follow-up. This build ships **clean video HDMI only** — the HDMI display will show the camera feed but no live audio. Recording audio into the file is unaffected.

---

## How It Fits the Existing App (verified July 6, 2026)

| Existing piece                                | Role in HDMI feature                                                                                                              |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `CameraService.session` (`AVCaptureSession`)  | Single session — video flows from here. HDMI preview taps in with a second layer.                                                 |
| `CameraService.previewSession`                | Public read-only accessor — HDMI window uses it directly. Already declared in `CameraServiceProtocol`.                            |
| `CameraViewModel.session`                     | Forwarded from `previewSession` — already passed to `CameraPreviewView` on iPhone.                                                |
| `CameraPreviewView` / `PreviewView`           | Uses `AVCaptureVideoPreviewLayer`. A second, gesture-free version is created for the HDMI window.                                 |
| `PromptCamApp` / `WindowGroup`                | Unchanged — an additional external-display scene is declared in the scene manifest and handled by a dedicated `SceneDelegate`.    |

> [!IMPORTANT]
> `AVCaptureVideoPreviewLayer` supports **multiple instances per session**. Two preview layers can connect to the same running `AVCaptureSession` with no conflicts and no session restart.

> [!NOTE]
> **iOS 18+ requires scene-based external display handling.** `UIScreen.didConnectNotification` / `screens` are deprecated in favor of a second `UIWindowScene` with role `UIWindowSceneSessionRoleExternalDisplayNonInteractive`. That's the approach used here.

---

## Files Delivered

| File                                                        | Purpose                                                                                                              |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `PromptCam/Services/ExternalDisplayService.swift`           | `@MainActor` singleton. Owns the external window; wires session into `CleanOutputView`.                              |
| `PromptCam/App/ExternalSceneDelegate.swift`                 | `UIWindowSceneDelegate` that forwards attach/detach to the service.                                                  |
| `PromptCam/Views/ExternalDisplay/CleanPreviewView.swift`    | Gesture-free `UIViewRepresentable` wrapping `PreviewView` with `.resizeAspectFill`.                                  |
| `PromptCam/Views/ExternalDisplay/CleanOutputView.swift`     | Black background + full-screen `CleanPreviewView`.                                                                   |
| `PromptCam/Info.plist`                                      | Explicit `UIApplicationSceneManifest` declaring both the app scene and the external-display scene role.              |
| `project.yml`                                               | `INFOPLIST_KEY_UIApplicationSceneManifest_Generation: NO` so the explicit Info.plist declaration wins.               |
| `PromptCam/ViewModels/CameraViewModel.swift`                | One-line `ExternalDisplayService.shared.configure(session:)` call in `onAppear()`.                                   |

`CameraService.swift` is **untouched**.

---

## Audio Monitoring (Follow-up)

The `AVAudioEngine` approach for iOS mic monitoring:

```swift
let engine = AVAudioEngine()
let input = engine.inputNode
engine.connect(input, to: engine.mainMixerNode, format: input.inputFormat(forBus: 0))
engine.mainMixerNode.outputVolume = 1.0
try engine.start()
```

Complications:

- `AVAudioEngine` and `AVCaptureSession` may contend for the mic; needs a shared `AVAudioSession` category (`.playAndRecord`, already set) and route-change coordination with `AudioMeterService`.
- Needs auto-mute when no external route is present (otherwise mic → phone speaker feedback).
- Should be a separate service with its own tests; not folded into `ExternalDisplayService`.

---

## What Does NOT Change

- `AVCaptureSession` — no restart, no reconfiguration, no new outputs
- `CameraService.swift` — untouched
- `CameraPreviewView.swift` — iPhone preview unchanged
- `CameraView.swift` — no layout changes
- `AudioMeterService.swift` — unchanged
- All recording logic — recordings save to device normally
- `PromptCamApp.swift` — `WindowGroup` unchanged; external window handled by SceneDelegate

---

## Verification Plan

| Test                                | Expected result                                                                              |
| ----------------------------------- | -------------------------------------------------------------------------------------------- |
| Connect adapter → monitor           | External display shows full-screen camera feed, black background                             |
| Disconnect adapter mid-session      | iPhone continues normally, external window torn down, no crash                               |
| Tap focus on iPhone                 | HDMI feed updates (same session); no touch events on HDMI side                               |
| Record while HDMI connected         | Recording saves to device normally; mic audio in file unchanged                              |
| Switch Standard ↔ Cinematic         | HDMI preview follows session (same layer)                                                    |
| Connect HDMI before app launch      | Scene delegate fires at launch; service attaches once camera session is configured           |
| AirPlay to Apple TV (non-mirrored)  | Same code path — AirPlay presents as external scene                                          |
| Screen mirroring / QuickTime        | Shows full iPhone UI (expected — mirroring is not the same as external scene)                |
| No adapter connected                | Zero performance impact — service holds session ref but does nothing                         |
