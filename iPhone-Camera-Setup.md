# PromptCam — iPhone Camera Setup

_June 14, 2026 — GitHub Copilot (Claude Sonnet 4.6)_

---

## Overview

PromptCam uses AVFoundation to record video from the front-facing camera with two modes: **Standard** and **Cinematic**. The user picks mode, resolution, and frame rate. The app silently routes to the correct physical hardware.

---

## Physical Device Routing

The key architectural decision: **Standard and Cinematic use different physical AVCaptureDevice instances**.

| User Selection | Physical Device                  | Why                                      |
| -------------- | -------------------------------- | ---------------------------------------- |
| Standard       | `builtInWideAngleCamera` (front) | Full resolution + frame rate flexibility |
| Cinematic      | `builtInTrueDepthCamera` (front) | Only device with CINE-flagged formats    |

This was discovered by dumping all camera formats on first launch. Cinematic formats (`minSimulatedAperture != 0` on iOS 26+) exist **exclusively** on the TrueDepth device — the wide-angle has none. iOS Camera app does the same swap silently.

```swift
private func preferredDevice(for mode: VideoMode) -> AVCaptureDevice? {
    switch mode {
    case .cinematic:
        return AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    case .standard:
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }
}
```

---

## Session Configuration

`configureSession(format:)` runs once on first launch (idempotent):

1. Set session preset for the requested resolution
2. Call `preferredDevice(for: format.mode)` to get the right hardware
3. Create `AVCaptureDeviceInput` → add to session → **retain reference** as `self.videoInput`
4. Add audio input (`builtInMicrophone`)
5. Add `AVCaptureMovieFileOutput`
6. If cinematic: call `findCinematicFormat()` → set `device.activeFormat` → enable `isCinematicVideoCaptureEnabled`
7. Apply frame rate via `applyFrameRate(_:to:)`
8. Dump all formats to console (debug)
9. Run `queryDeviceCapabilities()` → publish to ViewModel via `onDeviceCapabilitiesQueried`

---

## Mode Switching (applyFormat)

When the user changes mode in the Format Panel, `applyFormat(_:)` runs inside `beginConfiguration/commitConfiguration`:

1. Call `preferredDevice(for: format.mode)` — compare `uniqueID` with current device
2. If device changed: remove old `videoInput`, create new `AVCaptureDeviceInput`, add to session
3. **Cinematic path**: call `findCinematicFormat()` to pick a CINE format matching resolution + FPS, set `device.activeFormat`, then set `isCinematicVideoCaptureEnabled = true`
4. **Standard path**: set session preset for resolution, call `disableCinematicCapture()`
5. Apply frame rate
6. Publish `RecordingFormat` with `appliedMode` (reverts to `.standard` if cinematic setup failed)

---

## Cinematic Format Detection

`findCinematicFormat(for:resolution:frameRate:)` searches only the given device's own formats:

```
iOS 26+  → format.minSimulatedAperture != 0
pre-iOS26 → !format.supportedDepthDataFormats.isEmpty
```

Matching priority: correct dimensions → CINE flag → frame rate supported.

### iPhone 13 Example (TrueDepth, iOS 26)

From the live format dump:

```
[26] 1920x1080 2-30fps [CINE(f/2.0-16.0 def:4.5) DEPTH(12) HDR]
[28] 1920x1080 2-30fps [CINE(f/2.0-16.0 def:4.5) DEPTH(12)]
[41] 3088x2316 2-30fps [CINE(f/1.4-16.0 def:4.5) DEPTH(12) HDR]
[50] 4032x3024 2-30fps [CINE(f/1.4-16.0 def:4.5) DEPTH(12) HDR]
```

HD 30fps → format [26] or [28].

---

## Capability Detection

`queryDeviceCapabilities()` always queries **both cameras independently**, regardless of which is currently active:

- **Standard capabilities** → scanned from wide-angle device formats
- **Cinematic availability** → scanned from TrueDepth device formats (`minSimulatedAperture != 0`)
- Returns `DeviceCapabilities` struct with per-mode resolution and FPS lists
- This drives the Format Panel UI: which options are enabled, which are greyed out

---

## Simulated Aperture (f-stop)

When cinematic mode is active (iOS 26+ + TrueDepth), the app fires `onCinematicApertureAvailable(min, max, default)` to the ViewModel.

- Range comes from `format.minSimulatedAperture` / `maxSimulatedAperture` / `defaultSimulatedAperture`
- Example on iPhone 13 front camera: **f/2.0 – f/16.0, default f/4.5**
- Live adjustment via `input.simulatedAperture = clampedValue` (blocked during recording)
- A `CinematicAperturePanel` (f-stop slider) appears in the camera header when active, disappears when switching back to Standard

---

## Key Lessons Learned

### 1. CINE formats live on TrueDepth, not wide-angle

The front-facing wide-angle camera has zero `CINE` formats. Trying to set depth/cinematic formats on it causes `FigCaptureSourceRemote err=-17281` crashes. The correct device is `builtInTrueDepthCamera`.

### 2. isCinematicVideoCaptureSupported is per-input

`AVCaptureDeviceInput.isCinematicVideoCaptureSupported` (iOS 26+) is only accurate for the specific input added to the session. Using it on the wide-angle input to check if "cinematic is available" always returns `false`, even on capable devices, because cinematic lives on the TrueDepth input.

### 3. Do not use DiscoverySession results cross-device

Iterating `DiscoverySession.devices` and checking formats across all cameras then applying a found format to a different device crashes AVFoundation. Format selection must stay on the same device instance.

### 4. The iOS 26 API name

- Property: `isCinematicVideoCaptureEnabled` (not `cinematicVideoCaptureEnabled`)
- Supported check: `isCinematicVideoCaptureSupported`
- Both live on `AVCaptureDeviceInput`, not `AVCaptureDevice` or `AVCaptureDevice.Format`

### 5. Capability detection must be device-specific

Using `minSimulatedAperture != 0` on TrueDepth formats correctly identifies cinematic. Using it on wide-angle returns nothing. `queryDeviceCapabilities()` now explicitly checks TrueDepth for cinematic and wide-angle for standard, regardless of which is active.

---

## Threading Model

All AVFoundation work runs on `sessionQueue` (serial). Results reach the ViewModel via `@MainActor @Sendable` callbacks:

| Callback                       | Fires When                                             |
| ------------------------------ | ------------------------------------------------------ |
| `onDeviceCapabilitiesQueried`  | After session configure or format change               |
| `onFormatApplied`              | Format change confirmed with actual applied values     |
| `onCinematicApertureAvailable` | Cinematic enabled — carries (min, max, default) f-stop |
| `onSessionRunningStateChanged` | Session starts/stops                                   |
| `onRecordingStateChanged`      | Recording starts/stops                                 |
| `onError`                      | Any camera error                                       |

---

## Files Modified

| File                                        | Role                                                 |
| ------------------------------------------- | ---------------------------------------------------- |
| `Services/CameraService.swift`              | All camera hardware logic                            |
| `ViewModels/CameraViewModel.swift`          | State + callback binding; aperture state             |
| `Views/Camera/CinematicAperturePanel.swift` | f-stop slider UI                                     |
| `Views/Camera/CameraTopControlsView.swift`  | Aperture button in header                            |
| `Views/CameraView.swift`                    | Aperture panel layer + mutual exclusion              |
| `Views/Sheets/CameraFormatPanelSheet.swift` | Mode/resolution/FPS picker with capability gating    |
| `Views/Camera/VideoModeBadgeView.swift`     | STD / CINE badge in header                           |
| `Models/RecordingFormat.swift`              | `VideoMode` enum + `RecordingFormat` with mode field |
