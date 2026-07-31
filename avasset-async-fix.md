# Async / Thread-Blocking Fix Plan

## Background

Four places in the codebase call blocking PhotoKit or AVAudioSession APIs on the
main thread. Each one can cause UI jank; the audio engine items also risk the
camera-preview freeze already seen in production.

---

## Issue 1 — `AudioMeterService`: engine and session ops on main actor (HIGH)

**Where**: `AudioMeterService.startMetering()`, `ensureSessionConfigured()`,
`reconnectIfPending()`

**What blocks**:

- `AVAudioSession.setCategory + setActive(true)` — syscalls with variable latency
- `AVAudioEngine.inputNode.outputFormat(forBus:)`, `installTap(...)`, `engine.start()`

**Why it matters**: `AudioMeterViewModel.setup()` is `@MainActor`, so all of the
above runs synchronously on the main thread on every session start and every
interruption-recovery restart.

**Fix**:

1. Add a dedicated serial queue to `AudioMeterService`:

   ```swift
   private let meterQueue = DispatchQueue(
       label: "com.rgriola.promptcam.audiometer", qos: .userInitiated)
   ```

2. Dispatch the body of `startMetering()` (from `ensureSessionConfigured()` through
   `engine.start()`) onto `meterQueue`. State guarded by `stateLock` is already
   thread-safe; `isSessionConfigured`, `audioEngine`, and related fields need the
   same `stateLock` treatment or must be accessed only from `meterQueue`.

3. In `reconnectIfPending()`, dispatch `setActive(true)` and the `restartEngine`
   call onto `meterQueue` before returning to main.

4. `tearDownEngine()` must also run on `meterQueue` to avoid racing a concurrent
   `startMetering()` call.

**Acceptance**: Instruments Time Profiler shows no `setCategory`/`setActive`/
`engine.start` frames on the main thread.

---

## Issue 2 — `RecordingsLibrarySheet`: `PHAsset.fetchAssets` on main actor (HIGH)

**Where**: [RecordingsLibrarySheet.swift](PromptCam/Views/Sheets/RecordingsLibrarySheet.swift) — two call sites

**What blocks**:

- `openPlayer(for:)` fast-path: `PHAsset.fetchAssets(withLocalIdentifiers:)` called
  inside an `@MainActor` async function before any async hop.
- `.onChange(of: selectedRecording)` Task: same call inside a `Task { }` that
  inherits main-actor isolation.

`RecordingsService` documents this as ~7 ms / 78% CPU per call on iPhone 13.

**Fix**:

In `openPlayer(for:)`, wrap the fetch in `Task.detached`:

```swift
if let identifier = item.itemIdentifier {
    let asset = await Task.detached(priority: .userInitiated) {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }.value
    if let asset {
        selectedRecording = Recording(asset: asset)
        return
    }
}
```

In the `.onChange` handler, use `Task.detached` the same way and hop back to
`MainActor.run { }` to assign `videoURL`.

**Acceptance**: Tapping a video in the picker produces no main-thread hitch visible
in Instruments; the `PHAsset.fetchAssets` frame appears on a non-main thread.

---

## Issue 3 — `RecordingsService.latestVideoThumbnail`: synchronous fetch on calling actor (MEDIUM)

**Where**: [RecordingsService.swift](PromptCam/Services/RecordingsService.swift) `latestVideoThumbnail(targetSize:)`

**What blocks**: `PHAsset.fetchAssets(with: .video, options:)` runs synchronously
before the async `withCheckedContinuation` image-request hop. Called from
`CameraFooterControlsView`'s `.task` modifier, which runs on the main actor.

**Fix**:

Move the fetch inside a `Task.detached` block, or reuse the existing `cachingQueue`:

```swift
func latestVideoThumbnail(targetSize: CGSize) async -> UIImage? {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard status == .authorized || status == .limited else { return nil }

    guard let asset = await Task.detached(priority: .userInitiated) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: .video, options: options).firstObject
    }.value else { return nil }

    // existing withCheckedContinuation image request...
}
```

**Acceptance**: No `PHAsset.fetchAssets` frame on the main thread when the footer
thumbnail refreshes after a recording saves.

---

## Issue 4 — `RecordingsService.asset(for:)` called from `@MainActor` contexts (LOW)

**Where**: `RecordingsService.thumbnail(for:)` and `resolveURL(for:)`, both reached
from `@MainActor` call sites in `RecordingsLibraryViewModel` and `RecordingPlayerView`.

**What blocks**: `PHAsset.fetchAssets(withLocalIdentifiers:)` inside `asset(for:)`
runs synchronously on whatever actor invokes `thumbnail` or `resolveURL`. When the
cache misses, this blocks the main thread.

**Fix**: Mark `thumbnail(for:)` and `resolveURL(for:)` as `nonisolated` and ensure
the `asset(for:)` lookup is wrapped in a `Task.detached` inside each function, or
route all callers through an existing `Task.detached` before calling the service.

Alternatively, extract the asset-resolution step into a dedicated async helper that
always dispatches onto `cachingQueue` via a checked continuation.

**Acceptance**: Cache-miss path for a carousel thumbnail does not appear on the main
thread in Time Profiler.

---

## Testing Checklist

- [ ] Session start: no jank on `CameraView` appear
- [ ] Interruption recovery (simulate with Control Center): no preview freeze
- [ ] Tap video in `RecordingsLibrarySheet`: picker opens without dropped frames
- [ ] Footer thumbnail refresh after recording stops: no main-thread hitch
- [ ] Carousel scroll on `RecordingPlayerView`: thumbnail loads without stall
- [ ] Existing unit tests pass (`PromptCamTests`)
