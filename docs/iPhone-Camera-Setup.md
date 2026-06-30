# PromptCam — iPhone Camera Setup

_June 14, 2026 — GitHub Copilot (Claude Sonnet 4.6)_
_Updated June 14, 2026 — multi-device routing, pixel-threshold format matching_

---

## Overview

PromptCam uses AVFoundation to record video from the front-facing camera with two modes: **Standard** and **Cinematic**. The user picks mode, resolution, and frame rate. The app silently routes to the correct physical hardware — which varies by device generation.

---

## Physical Device Routing

The key architectural decision: **Standard and Cinematic use different physical `AVCaptureDevice` instances**, and which device carries CINE formats varies by hardware.

| User Selection | Physical Device                        | Why                                                   |
| -------------- | -------------------------------------- | ----------------------------------------------------- |
| Standard       | `builtInWideAngleCamera` (front)       | Full resolution + frame rate flexibility              |
| Cinematic      | Best-matching front device (see below) | CINE formats live on different cameras per generation |

### Why routing is not hardcoded

Discovered from live format dumps across devices:

| Device        | CINE formats on…                                                                            |
| ------------- | ------------------------------------------------------------------------------------------- |
| iPhone 13     | `builtInTrueDepthCamera` — `1920x1080`, `3088x2316`, `4032x3024`                            |
| iPhone 17 Pro | `builtInUltraWideCamera` — `1920x1080`, `3840x2160`; TrueDepth has `3088x2316`, `4032x3024` |

The app scans **all** front cameras and picks whichever has a CINE format closest to the target resolution.

```swift
private func bestCinematicDevice(for resolution: VideoResolution) -> AVCaptureDevice? {
    // targetPixels: 1920*1080 for HD, 3840*2160 for 4K
    // Scans all front devices, returns the one whose CINE format
    // has pixel count closest to target.
}

private func preferredDevice(for mode: VideoMode, resolution: VideoResolution) -> AVCaptureDevice? {
    switch mode {
    case .standard:  return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    case .cinematic: return bestCinematicDevice(for: resolution)
                         ?? builtInTrueDepthCamera ?? builtInWideAngleCamera
    }
}
```

---

## Session Configuration

`configureSession(format:)` runs once on first launch (idempotent):

1. Set session preset for the requested resolution
2. Call `preferredDevice(for: format.mode, resolution: format.resolution)` to get the right hardware
3. Create `AVCaptureDeviceInput` → add to session → **retain reference** as `self.videoInput`
4. Add audio input (`builtInMicrophone`)
5. Add `AVCaptureMovieFileOutput`
6. If cinematic: call `findCinematicFormat()` → set `device.activeFormat` → enable `isCinematicVideoCaptureEnabled`
7. Apply frame rate via `applyFrameRate(_:to:)`
8. Dump all formats to console (one-time debug)
9. Run `queryDeviceCapabilities()` → publish to ViewModel via `onDeviceCapabilitiesQueried`

---

## Mode Switching (applyFormat)

When the user changes mode or resolution in the Format Panel, `applyFormat(_:)` runs inside `beginConfiguration/commitConfiguration`:

1. Call `preferredDevice(for: format.mode, resolution: format.resolution)` — resolution is passed because HD and 4K cinematic may route to different physical cameras on some devices
2. If the target device's `uniqueID` differs from the current one: remove old `videoInput`, create and add new `AVCaptureDeviceInput`
3. **Cinematic path**: call `findCinematicFormat()` → set `device.activeFormat` → set `isCinematicVideoCaptureEnabled = true`
4. **Standard path**: set session preset for resolution, call `disableCinematicCapture()`
5. Apply frame rate
6. Report applied resolution from `device.activeFormat` dimensions (not session preset — preset is not set in cinematic mode)
7. Publish `RecordingFormat` with `appliedMode` (reverts to `.standard` if cinematic setup failed)

---

## Cinematic Format Selection

`findCinematicFormat(for:resolution:frameRate:)` searches the given device's own formats only (never cross-device).

**CINE detection:**

```
iOS 26+   → format.minSimulatedAperture != 0
pre-iOS26 → !format.supportedDepthDataFormats.isEmpty
```

**Size class split** — fixed 5.2MP threshold (midpoint between 1080p and 4K):

- `pixels ≤ 5,184,000` → HD class
- `pixels > 5,184,000` → 4K class

**Selection priority within the size class:**

1. Closest pixel count to standard target (1,920×1,080 or 3,840×2,160) + exact fps match
2. Closest pixel count + fps fallback (nearest max fps to desired)

This works regardless of the actual dimensions stored on a given device.

### Examples

| Device        | User requests | CINE device | Format selected                     |
| ------------- | ------------- | ----------- | ----------------------------------- |
| iPhone 13     | HD 30fps      | TrueDepth   | `1920x1080 @ 30fps`                 |
| iPhone 13     | 4K 30fps      | TrueDepth   | `3088x2316 @ 30fps` (closest to 4K) |
| iPhone 17 Pro | HD 30fps      | UltraWide   | `1920x1080 @ 30fps`                 |
| iPhone 17 Pro | 4K 30fps      | UltraWide   | `3840x2160 @ 30fps`                 |

---

## Capability Detection

`queryDeviceCapabilities()` scans **all front cameras** via `DiscoverySession`, independently of which device is currently active:

- **Standard** → scanned from wide-angle device formats (session-preset gated)
- **Cinematic** → 5.2MP threshold classifies each CINE format as HD or 4K
- Returns `DeviceCapabilities` struct driving the Format Panel UI (which options are enabled/greyed)

---

## Simulated Aperture (f-stop)

When cinematic mode is enabled (iOS 26+), `enableCinematicCapture(on:)` fires `onCinematicApertureAvailable(min, max, default)` to the ViewModel.

- Range read from `device.activeFormat.minSimulatedAperture` / `maxSimulatedAperture` / `defaultSimulatedAperture` after enabling cinematic on the input
- Example: **f/1.4 – f/16.0, default f/4.5** (iPhone 13 / 17 Pro front)
- Live adjustment via `input.simulatedAperture = clampedValue` (blocked during recording)
- `CinematicAperturePanel` (f-stop slider) appears in the camera header — auto-dismissed when switching back to Standard

---

## Key Lessons Learned

### 1. CINE formats are NOT always on TrueDepth

On iPhone 13, CINE lives on TrueDepth. On iPhone 17 Pro, standard HD/4K CINE lives on the **UltraWide** front camera; TrueDepth has only unusual portrait-sensor sizes (`3088x2316`, `4032x3024`). Always scan all front cameras.

### 2. Never apply a format from one device to another

Iterating `DiscoverySession.devices`, finding a CINE format on device A, then setting `device.activeFormat` on device B causes `FigCaptureSourceRemote err=-17281` crashes. Format selection and application must use the same device instance.

### 3. Session preset is not set in cinematic mode

`applyFormat` sets `device.activeFormat` directly. The session preset remains at its previous value and cannot be used to infer applied resolution. Read `device.activeFormat.formatDescription` dimensions instead.

### 4. `isCinematicVideoCaptureSupported` is per-input, post-add

`AVCaptureDeviceInput.isCinematicVideoCaptureSupported` (iOS 26+) is only meaningful after the input has been added to the session. Checking it on a wide-angle input returns `false` even on capable devices, because that input doesn't carry CINE capability.

### 5. The iOS 26 API names

- `isCinematicVideoCaptureEnabled` (not `cinematicVideoCaptureEnabled`) — settable on `AVCaptureDeviceInput`
- `isCinematicVideoCaptureSupported` — read-only on `AVCaptureDeviceInput`
- `minSimulatedAperture` / `maxSimulatedAperture` / `defaultSimulatedAperture` — on `AVCaptureDevice.Format` (iOS 26+)
- `simulatedAperture` — settable on `AVCaptureDeviceInput`

### 6. Pixel-threshold routing is more reliable than relative size ranking

Early versions used relative ranking (median split, smallest = HD). This broke when a single device had only large-pixel CINE formats. A fixed 5.2MP threshold (between standard 1080p and 4K target pixel counts) is stable across all known devices.

---

## Threading Model

All AVFoundation work runs on `sessionQueue` (serial). Results reach the ViewModel via `@MainActor @Sendable` callbacks:

| Callback                       | Fires When                                                                 |
| ------------------------------ | -------------------------------------------------------------------------- |
| `onDeviceCapabilitiesQueried`  | After session configure or format change                                   |
| `onFormatApplied`              | Format change confirmed with actual applied values                         |
| `onCinematicApertureAvailable` | Cinematic enabled — carries (min, max, default) f-stop; (0,0,0) = disabled |
| `onSessionRunningStateChanged` | Session starts/stops                                                       |
| `onRecordingStateChanged`      | Recording starts/stops                                                     |
| `onError`                      | Any camera error                                                           |

---

## Files

| File                                          | Role                                                 |
| --------------------------------------------- | ---------------------------------------------------- |
| `Services/CameraService.swift`                | All camera hardware logic                            |
| `ViewModels/CameraViewModel.swift`            | State + callback binding; aperture state             |
| `Views/Camera/CinematicAperturePanel.swift`   | f-stop slider UI                                     |
| `Views/Camera/CameraTopControlsView.swift`    | Aperture button in header                            |
| `Views/Camera/CameraFooterControlsView.swift` | Guide icon (moved from header)                       |
| `Views/CameraView.swift`                      | Aperture panel layer + mutual exclusion              |
| `Views/Sheets/CameraFormatPanelSheet.swift`   | Mode/resolution/FPS picker with capability gating    |
| `Views/Camera/VideoModeBadgeView.swift`       | STD / CINE badge in header                           |
| `Models/RecordingFormat.swift`                | `VideoMode` enum + `RecordingFormat` with mode field |
