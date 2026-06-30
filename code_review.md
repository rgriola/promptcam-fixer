# PromptCam Code Review

Full codebase audit — organized by severity. Each item links to the source.

---

## 🔴 Dead Code — Safe to Remove

These are unused or vestigial items that add confusion without serving any purpose.

### 1. `PreferredCameraSelection` enum + method — never called
[CameraService.swift:12-16](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/CameraService.swift#L12-L16) and [L192-197](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/CameraService.swift#L192-L197)

The enum `PreferredCameraSelection` and `preferredCameraSelection(frontAvailable:backAvailable:)` are defined but never used anywhere. The `backAvailable` parameter is silently ignored. Dead code from an earlier design.

### 2. Legacy `onSupportedFormatsQueried` callback — fully superseded
The entire callback chain `onSupportedFormatsQueried` across 3 files is now a legacy shim. After the capabilities refactor, `onDeviceCapabilitiesQueried` is the sole consumer and provides strictly more information. The old callback populates two ViewModel properties that **nothing reads**:

| Property | File | Used by any View? |
|---|---|---|
| `supportedResolutions` | [CameraViewModel.swift:103](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/ViewModels/CameraViewModel.swift#L103) | ❌ No |
| `supportedFrameRates` | [CameraViewModel.swift:105](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/ViewModels/CameraViewModel.swift#L105) | ❌ No |

The fallback logic in `onSupportedFormatsQueried` (L454-465) is also duplicated by `onDeviceCapabilitiesQueried` (L468-480) which does the same check with `isSupported` + `adjusted`.

**Recommendation:** Remove `onSupportedFormatsQueried` from `CameraServiceProtocol`, `CameraService`, and the ViewModel. Remove `supportedResolutions` / `supportedFrameRates` properties.

### 3. Commented-out `FocusIndicatorView` — 3 locations
[CameraView.swift:77-83](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L77-L83), [L378-379](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L378-L379), [L482-483](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L482-L483)

The focus reticle was turned off Jun 11. All three blocks are dead. The `@State` properties `focusIndicatorPoint`, `showFocusIndicator`, `hideFocusTask` and the methods `updateFocusIndicatorPosition`, `scheduleFocusHide`, `cleanupFocusState` are also dormant — they write state that nothing renders.

**Recommendation:** Either delete these entirely or create a proper feature flag (e.g. `showFocusReticle = false` in a config) instead of scattered comment blocks.

### 4. Dead `_ =` expression
[CameraViewModel.swift:538](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/ViewModels/CameraViewModel.swift#L538)
```swift
_ = !wasExternalBefore && isExternal  // built-in → external (future use)
```
This evaluates a boolean and discards it. It's a placeholder comment that shouldn't be executable code.

### 5. `onTapGuide` / Guide button — empty handler
[CameraView.swift:461-463](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L461-L463)
```swift
onTapGuide: {
    // Tour disabled — guide button reserved for future use.
}
```
The guide/paw button in the footer is visible and tappable but does nothing. Either hide it or wire it.

---

## 🟡 Architecture & Robustness

### 6. `CameraViewModel` is doing too much — 668 lines, 30+ `@Observable` properties

The ViewModel is the single state object for camera, audio, teleprompter, recording format, modal routing, style persistence, and metering. There's no functional problem, but it's hard to reason about which state changes trigger which redraws.

**Low-effort wins:**
- Extract **teleprompter state** (`config`, `isScrolling`, `resetToken`, style persistence) into a `TeleprompterViewModel` — ~120 lines that have zero interaction with camera/audio.
- Extract **audio state** (`audioLevel`, `audioPeak`, `isStereoInput`, `isExternalMic`, etc.) into an `AudioStateViewModel` — ~100 lines of pure data flow from `AudioMeterService`.

### 7. `CameraService.deinit` mutates session from arbitrary queue
[CameraService.swift:186-190](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/CameraService.swift#L186-L190)
```swift
deinit {
    session.stopRunning()
    for input in session.inputs { session.removeInput(input) }
    for output in session.outputs { session.removeOutput(output) }
}
```
`deinit` can fire on any thread, but `AVCaptureSession` mutations should happen on `sessionQueue`. In practice this rarely triggers because the service lives as long as the app, but it's technically undefined behavior and a real crash risk if the lifecycle changes.

### 8. `CameraView` magic numbers
[CameraView.swift:109](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L109), [L113](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L113), [L134](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L134), [L142](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L142), [L153](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L153), [L176](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L176)

Scattered literals like `+ 5`, `- 89`, `- 125`, `- 200`, `+ 100`, `- 75`. These are hard to maintain and break on different screen sizes. `CameraLayout.swift` exists and already defines structured layout constants — move these remaining magic numbers there.

### 9. Double-format-fallback: `onSupportedFormatsQueried` AND `onDeviceCapabilitiesQueried` both do format adjustment
The old callback does a flat-array `contains` check and falls back. The new callback does `capabilities.isSupported` + `capabilities.adjusted`. If both fire (they do, sequentially in [CameraService.swift:438-444](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/CameraService.swift#L438-L444)), the format may be adjusted twice — first by the legacy path, then overwritten by the new path. This is harmless but wasteful and confusing. Resolves itself when item #2 above is cleaned up.

### 10. Inline comment block in CameraView — orphaned design notes
[CameraView.swift:156-157](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift#L156-L157)
```swift
// Screen height - camera preview height > remaninder 2000 - 1400 = 600 Or a ratio.   Subtracrt y = 1400...
```
This is stale developer notes with typos, not actionable code or documentation.

---

## 🟢 Quality & Polish

### 11. `Float.clamped(to:)` global extension
[CameraService.swift:507-512](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/CameraService.swift#L507-L512)

This extends `Float` globally but is only used within `CameraService+Format.swift`. Move it to a `private extension Float` scoped to that file, or use Swift's built-in `min(max(...))` pattern which is already used elsewhere in the same file.

### 12. `#available(iOS 13.0, *)` guard is always true
[CameraService+Format.swift:413](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/CameraService+Format.swift#L413)
```swift
if #available(iOS 13.0, *) {
```
The app's minimum deployment target is iOS 16+ (SwiftUI + Observation). This check is always `true` and just adds dead branches.

### 13. `allVideoDeviceTypes()` is `func` but should be `static` or a computed property
[CameraService+Format.swift:408](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/CameraService+Format.swift#L408)

It references no instance state. Making it `static` or a module-level computed var would prevent accidental instance dependencies and make intent clearer.

### 14. Recording temp file naming uses `abs(hashValue)` — collision risk
[RecordingsService.swift:115](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/RecordingsService.swift#L115)
```swift
.appendingPathComponent("PromptCam-\(abs(recording.id.hashValue)).\(ext)")
```
`hashValue` is not stable across runs and `abs(Int.min)` overflows. Use `recording.id` directly (it's already a UUID string) or `UUID().uuidString` for uniqueness.

### 15. No unit tests
There are no test targets in the project. `CameraServiceProtocol` exists specifically to enable mocking — the abstraction is there, but no tests exercise it. Even a few tests around `DeviceCapabilities.isSupported`, `adjusted`, and `RecordingFormat` persistence would catch regressions cheaply.

---

## Summary Prioritization

| Priority | Items | Effort |
|---|---|---|
| **Quick wins** (30 min) | #1, #2, #3, #4, #5, #10, #11, #12, #14 | Delete dead code, fix collision risk |
| **Medium** (1-2 hr) | #7, #8, #9, #13 | deinit safety, layout constants, remove double-fallback |
| **Larger** (half day+) | #6, #15 | ViewModel decomposition, test harness |

Let me know which items you'd like to tackle — or if you want me to just batch all the quick wins into a cleanup commit.
