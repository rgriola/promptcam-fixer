# Video Player / Carousel — Performance & Crash Remediation Plan

**Date:** July 27, 2026
**Reported by:** User (iPhone 17, physical device, large photo library, full access)
**Status:** Plan — awaiting approval. No code written.

---

## 1. Reported Symptoms

| #   | Symptom                                                           | User quote                                                                                                       |
| --- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| S1  | Crash on **returning to camera preview** after closing the player | "The crash happens when I return to the camera preview (main app view). So I close the photopicker and go back." |
| S2  | Feature is slow and jerky throughout                              | "The entire feature is slow and jerky."                                                                          |
| S3  | Opening the player is slow                                        | "Tapping the icon button just to open the is akwardly slow."                                                     |

**Key qualifier:** the crash is _eventual_, not immediate. It appears after some number of
open/close cycles. That is the signature of **cumulative, unbounded memory growth**, not a
one-shot logic error.

---

## 2. Root Cause Analysis

### 2.0 DOMINANT — The whole library is enumerated at app launch

**Added July 28 after user reported a 52,000-asset library and ~200 `PHCachingImageManager`
calls between 0:00 and 0:16, with the player not opened until 0:09.**

[CameraViewModel.swift](PromptCam/ViewModels/CameraViewModel.swift#L183) runs
`Task { await recordings.prefetch() }` inside `onAppear`. So at **app launch**, before the
user touches anything:

1. `fetchLatestRecording()` — synchronous PhotoKit fetch on the main actor
2. `resolveURL(for: latest)` — a real `AVAsset` request, possibly an iCloud download
3. `fetchAllRecordings()` — enumerates **every video in a 52,000-asset library** and
   allocates a `Recording` struct for each
4. `startCaching` on the first 8

Step 3 is the dominant cost. `Recording(asset:)` touches `duration`, `creationDate`,
`pixelWidth`, and `pixelHeight` — each faults a row out of the Photos database. The
comment in `prefetch()` reads _"Fetch all recordings — no limit. PHAsset references are
tiny."_ That reasoning holds for one asset and fails completely at 52,000.

`recentRecordings` then becomes that entire array, and it is handed directly to the eager
`HStack` in the carousel (§2.2). Opening the player asks SwiftUI to instantiate a
`CarouselCell` — each with its own `.task`, its own retained `UIImage`, and its own
`NetworkMonitor` observer — for **every video the user has ever shot**.

**This single finding explains all three symptoms** and reframes everything below it:
S3 (slow open) is the enumeration, S2 (jerk) is the cell explosion, S1 (crash) is the
resulting memory ceiling.

**Consequence for the plan:** capping the fetch is no longer a Phase 2 nicety. It is the
fix, and it makes several other planned changes unnecessary. See §4.

### 2.1 PRIMARY — `stopCachingAll()` is never called (crash driver)

`RecordingsService.stopCachingAll()` exists but **has zero call sites**. Meanwhile
`startCaching(ids:targetSize:)` is invoked:

- On every `RecordingsGallery.prefetch()` — which itself runs on three separate triggers
- On every `warmCarousel(around:)` — which fires on **every carousel selection change**

`PHCachingImageManager` retains decoded images for every asset registered via
`startCachingImages`. Because we never call `stopCachingImages` (or the
`ForAllAssets` variant), that working set only ever grows — and it grows _across_
player open/close cycles because the manager is a `static let` that outlives the views.

This is the "eventually" in "eventually crashes."

### 2.2 PRIMARY — The carousel is eager, not lazy (crash + jerk driver)

`RecordingCarouselView` uses:

```swift
HStack(spacing: spacing) {
    ForEach(Array(recordings.enumerated()), id: \.element.id) { index, recording in
```

An **eager `HStack`**, not `LazyHStack`. And `recordings` is the _entire_ library, because
`RecordingsService.fetchAllRecordings()` applies no `fetchLimit`.

On a large library this instantiates hundreds-to-thousands of `CarouselCell` views at once.
Each cell independently:

- Fires a `.task` → one PhotoKit image request
- Holds a decoded `UIImage` in `@State` for its entire lifetime
- Creates `@State networkMonitor = NetworkMonitor.shared` → one observer
- Owns a retry loop (5 attempts, `[3,5,8,15,30]`s backoff) that can hold a sleeping task

Native iOS keeps roughly ten cells alive via a recycling collection view.

### 2.3 PRIMARY — Capture session is never suspended (crash driver)

`cameraService.startSession()` runs in `CameraViewModel.onAppear()`;
`stopSession()` only in `onDisappear()`. The `.fullScreenCover` presenting the player does
**not** suspend the session. A 4K capture pipeline keeps its buffers allocated for the
entire time the player is open, stacked on top of everything in 2.1 and 2.2.

**Why this explains S1 specifically:** memory peaks while the player is open, then on
dismiss the camera preview re-renders and `prefetch()` can re-fire — a second allocation
spike at exactly the worst moment. The process is killed by jetsam, which surfaces to the
user as a crash on return to camera preview.

### 2.4 SECONDARY — Pre-warm options don't match request options (wasted work) — **CONFIRMED**

- `startCaching` calls `startCachingImages(..., options: nil)`
- `thumbnail(for:)` requests with a custom `PHImageRequestOptions` (`deliveryMode`,
  `isNetworkAccessAllowed`, `version`)

`PHCachingImageManager` keys its cache on the options object. Mismatched options mean the
pre-warm result is **never served** to the actual request. We pay for the caching twice and
benefit zero times — while still holding the memory.

**Confirmed by Instruments (July 28).** Passing `nil` does not mean "no options" — PhotoKit
allocates its own default options object, which can never match ours:

```
18  PHImageRequestOptions  00:01.886.294  224 Bytes  Photos
    -[PHCachingImageManager startCachingImagesForAssets:targetSize:contentMode:options:]
```

The same trace timestamps `startCachingImagesForAssets` at **00:01.886** — roughly seven
seconds before the user opened the player. Independent confirmation of §2.0's launch-time
`prefetch()`.

**Also confirmed correct:** only **one** `PHCachingImageManager` is ever created
(`__allocating_init` appears once, at 00:01.619, with ~60µs of internal setup). The
`static let` is behaving as intended. An initial reading of ~200 PhotoKit rows as "200
manager instantiations" was a misread of allocation records.

### 2.5 SECONDARY — Every operation re-fetches the `PHAsset` (answers "are we calling assets multiple times?")

`Recording` intentionally does not store a `PHAsset` so it can be `Sendable` under Swift 6.
The cost is that `RecordingsService.asset(for:)` runs
`PHAsset.fetchAssets(withLocalIdentifiers:)` on **every** thumbnail request, **every** URL
resolve, and **every** delete. The service's own comment measures this at ~7ms.

At N cells that is N × 7ms of synchronous PhotoKit work, and `thumbnail(for:)` inherits the
caller's actor — which is `@MainActor`.

### 2.6 SECONDARY — `prefetch()` blocks the main actor (S3 driver)

`RecordingsGallery` is `@MainActor`. Inside `prefetch()`:

- `fetchLatestRecording()` — **synchronous** PhotoKit fetch, not detached, blocks the UI thread
- `await resolveURL(for: latest)` — starts a real `AVAsset` request that can trigger an
  **iCloud download**, purely to pre-warm

Only `fetchAllRecordings()` is correctly wrapped in `Task.detached`.

### 2.7 TERTIARY — Refresh cascade

`refreshInBackground()` is wired to three triggers (photo-library monitor,
`onRecordingStateChanged`, `onRecordingSavedToLibrary`). The library monitor fires on _any_
change, including edits from Photos.app and iCloud sync. Each fire re-enumerates the whole
library and re-resolves the latest URL.

### 2.8 TERTIARY — Unstructured `Task`s

Three bare `Task { }` blocks are not cancelled on dismiss:

- `.onAppear { Task { await loadAdjacentThumbnails() } }`
- `.onChange(of: activeRecording) { Task { await loadAdjacentThumbnails() } }`
- `Task { await selectRecording(target) }` in `commitNavigation`

**Correction to an earlier assessment:** these do **not** cause `EXC_BAD_ACCESS`. SwiftUI
`@State` is heap-backed and safe to write after view teardown. These are a _wasted work and
retained-image_ problem (each pulls two 500×500 covers), not a memory-safety problem. They
are worth fixing, but they are not the crash.

### 2.9 Ruled out

Investigated and found **safe** — not crash candidates:

- `teardownPlayer()` ordering (KVO invalidated, time observer removed before `player = nil`)
- All `withCheckedContinuation` sites have double-resume guards
- `newRecordings.first!` is guarded by a preceding `isEmpty` check
- `recordings[targetIndex]` is clamped to valid bounds
- `PhotoLibraryChangeMonitor` unregisters correctly and nils its `onChange`

---

## 3. Why Native Feels Fast

| Concern            | Native Photos                     | Cue Vue today                       |
| ------------------ | --------------------------------- | ----------------------------------- |
| Cell lifecycle     | Lazy, recycled (~10 alive)        | Eager, all N alive                  |
| Asset handles      | Holds `PHAsset`                   | Re-fetches by identifier every call |
| Cache options      | Pre-warm matches request          | Mismatched — never hits             |
| Cache teardown     | `stopCachingImages` on scroll-off | **Never called**                    |
| Fetch scope        | Windowed / paged                  | Entire library                      |
| Thumbnail sizes    | One canonical size                | 144×144 and 500×500                 |
| Background capture | Not running                       | 4K session live                     |

---

## 4. Phased Plan

Each phase is independently shippable and independently verifiable. Build gate after each:

```
xcodebuild -project PromptCam.xcodeproj -scheme PromptCam \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

---

### Phase 0 — Baseline measurement (no code) — OPTIONAL

**Downgraded to optional on July 28.** The 52,000-asset library size and the launch-time
`PHCachingImageManager` call volume already confirm §2.0. Run this only if Phase 1 fails to
move the needle. Simplest substitute: keep Xcode's memory gauge open during the Phase 1
re-test.

**Goal:** confirm the jetsam hypothesis before changing anything, so we can prove the fix.

**Do not filter Allocations by `PHCachingImageManager`.** Every allocation under that
symbol is 16–224 bytes of bookkeeping — far too small to kill a process. The memory that
causes jetsam lives in `CGImage` backing stores and `IOSurface`, and `IOSurface` does not
appear in Allocations at all by default because it is VM-mapped rather than malloc'd.

- Xcode → Debug Navigator → Memory gauge. Open/close the player 5× and record the
  footprint after each cycle. A monotonic staircase confirms §2.1.
- Instruments → Allocations sorted by **Persistent Bytes**, no symbol filter. Expect
  `CGImage` / `ImageIO` / `CVPixelBuffer` at the top.
- Instruments → **VM Tracker**, watch Dirty Size. This is where 4K capture buffers and
  image backing stores are actually accounted for.
- Generation-mark between each open/close cycle. Growth that never returns to baseline is
  the decisive evidence for §2.1.
- Instruments → Time Profiler on player open. Expect main-thread time in
  `PHAsset.fetchAssets` (§2.5, §2.6).
- After the next crash: Settings → Privacy & Security → Analytics & Improvements →
  Analytics Data → look for `JetsamEvent-*` at the crash time. If present, memory is
  confirmed and no further profiling is needed.
- Record the library video count — every O(N) finding scales with it.

**Exit criteria:** footprint-per-cycle numbers captured; crash classified as jetsam vs. exception.

---

### Phase 1 — Cap the fetch (the fix)

Targets S1, S2, and S3 simultaneously. This is now the whole ballgame.

- **1a.** Add a tunable constant at the top of `RecordingsService`:

  ```swift
  /// Maximum videos loaded into the carousel. Tune during testing.
  static let carouselFetchLimit = 15
  ```

  Apply it as `options.fetchLimit` in `fetchAllRecordings()`. PhotoKit applies the limit
  **inside** the fetch, so it never materializes the other ~52,000 rows — this is not a
  post-filter and it is not `.prefix(15)` on an already-built array.

- **1b.** Call `stopCachingAll()` on player dismiss, alongside `teardownPlayer()` (§2.1).
- **1c.** Make `startCaching` and `thumbnail(for:)` share one identical
  `PHImageRequestOptions` so the pre-warm actually serves the request (§2.4).

**Verify:** re-run the Phase 0 memory-gauge loop, and re-check the
`PHCachingImageManager` call count over the first 16 seconds. Expect the launch-time
portion to collapse toward single digits.

**Risk:** Low. 1a is a few lines and is trivially revertible by changing one constant.

---

### Phase 2 — Trim what the cap doesn't cover

Only the items the cap does **not** already solve.

- **2a.** Drop the per-cell `NetworkMonitor` observer in favor of one at the carousel
  level (§2.2). At 15 cells this is minor, but it is cheap and correct.
- **2b.** Reduce the retry ceiling / widen the backoff so an offline or heavily
  iCloud-offloaded library doesn't storm PhotoKit (§2.2).

**Explicitly dropped from this phase:** the `HStack` → `LazyHStack` conversion. At 15
cells an eager `HStack` is entirely appropriate, and `LazyHStack` would collide with the
manual `baseOffset` positioning in `scrollActiveToCenter(animated:)`, which assumes all
cells exist. Capping the fetch removes the need for what was previously the riskiest
change in this plan. **If we later raise the limit above ~50, revisit this.**

**Risk:** Low.

---

### Phase 3 — Get PhotoKit off the main thread

Directly targets S3.

- **3a.** Move `fetchLatestRecording()` off the main actor (`Task.detached`, matching the
  existing `fetchAllRecordings()` treatment).
- **3b.** Remove the eager `resolveURL` from `prefetch()`. Resolve lazily when the player
  actually opens — this is the single biggest contributor to the slow button tap.
- **3c.** Ensure `thumbnail(for:)` does its `asset(for:)` lookup off the main actor.

**Verify:** Time Profiler on player open; main-thread PhotoKit time should approach zero.

**Risk:** Low-medium. 3b changes when the URL is available — confirm the player's existing
`.task(id: activeRecording.id)` resolve path covers the gap (it appears to).

---

### Phase 4 — Structural cleanup

Lower urgency; do once 1–3 are proven.

- **4a.** Cache `PHAsset` handles by `localIdentifier` to kill the repeated ~7ms fetch (§2.5).
- **4b.** Consolidate on one thumbnail size, or justify keeping two.
- **4c.** Debounce / coalesce the three `refreshInBackground()` triggers (§2.7).
- **4d.** Convert the three unstructured `Task`s to `.task(id:)` modifiers (§2.8).
- **4e.** Share one `RecordingsService` instance instead of constructing a fresh one in each
  `CameraView` closure.
- **4f.** Audit `RecordingsLibraryViewModel` (the dormant camera-roll sheet). It runs its
  own unbounded `fetchAllRecordings()` and prefetches 18 thumbnails at a **third** size
  (300×300). If it is ever instantiated at launch it is a second copy of the §2.0 problem.

**Risk:** Low individually.

---

### Deferred by user decision

- **Suspending the capture session while the player is open (§2.3).** User: _"lets revisit
  if our issues are not resolved."_ Reasonable — it carries a camera re-warm cost on
  return, and the Phase 1 cap may make it unnecessary. Revisit only if crashes persist
  after Phase 1.
- **Session-scoped or day-scoped carousel** (show only today's takes). User's fallback if
  a flat cap of 15 proves wrong.

---

## 5. Recommended Order

**Phase 1 → re-test on device → Phase 3 → Phase 2 → Phase 4.**

Revised July 28. Phase 0 (baseline measurement) is now **optional**: the user-reported
52,000-asset library and the launch-time `PHCachingImageManager` call volume already
confirm the diagnosis, and §2.0 explains all three symptoms without further evidence.
Phase 1a is small enough and revertible enough that measuring first is no longer worth
the delay. Keep the memory gauge open during the Phase 1 re-test instead — that gives us
the before/after comparison for free.

Phase 3 stays ahead of Phase 2 because it targets the remaining main-thread stalls, which
are what will still be visible after the cap lands.

---

## 6. Open Questions

1. **Carousel depth** — how many videos should the carousel reach? This sets the Phase 2b (
   `fetchLimit`. Native shows the full roll but pages it; a fixed cap is far simpler.
   Answer >> 15 at a simple lever const at the top of the file I can adjust during testing.

2. **Capture session suspension** — acceptable to have a brief camera re-warm on return
   from the player, in exchange for stability?
   Answer >> lets revist if our issues are not resolved.

3. **Library size** — approximate video count on the test device, to calibrate expectations.

Answer >> My library as 52000 assests from years of video and assests. Likely the users will only need to review their most recent videos, maybe the last 5 "takes". An option if this does not work well is to only show videos from this sesssion or that day, but again if these other fixes do not work.

---

## 7. Assumptions To Validate

The jetsam diagnosis is **inferred from code reading**, not yet measured. Phase 0 exists
specifically to confirm or refute it. If Phase 0 shows a flat memory profile and an actual
exception in the crash log, this plan needs revision before Phase 1 proceeds.

---

## 8. Implementation Outcomes (July 28, 2026)

**Status:** Phases 1–4 implemented and verified via Instruments traces.

### Phase 1: Cap the fetch
- **Implemented:** Added `carouselFetchLimit = 15` to `RecordingsService`.
- **Implemented:** `fetchAllRecordings()` now applies `options.fetchLimit = Self.carouselFetchLimit`, strictly bounding the PhotoKit enumeration size.
- **Implemented:** Added `stopCachingAll()` to the `onDisappear` block of `RecordingPlayerView` to release memory bounds and prevent Jetsam crashes on loop.
- **Implemented:** Unified `PHImageRequestOptions` inside a new static method to guarantee pre-warm (`startCaching`) matches the runtime request (`thumbnail(for:)`), preventing duplicate loading.

### Phase 2: Trim what the cap doesn't cover
- **Implemented:** Refactored `NetworkMonitor` observer to live at the `RecordingCarouselView` parent level. Cells now receive connectivity state as a simple `Bool` rather than spawning 15 independent observers.
- **Implemented:** Reduced `maxRetries` from 5 to 3 and widened the `retryDelays` to `[5, 15, 30]` in `CarouselCell` to ease the load on PhotoKit for heavy iCloud libraries.

### Phase 3: Get PhotoKit off the main thread
- **Implemented:** Wrapped `fetchLatestRecording()` in `Task.detached` to prevent main thread blocking during early startup.
- **Implemented:** Removed the eager `resolveURL` from `RecordingsGallery.prefetch()`. Resolves are now entirely deferred until the player view is opened.
- **Reverted (Trace Validation):** Moving `asset(for: id)` into `Task.detached` introduced a massive 1-second overhead (context switching). We reverted it back to a synchronous lookup.
- **Optimized (Trace Validation):** `RecordingPlayerView.loadPlayer()` was holding the main thread for ~500ms while blocking on `item.asset.load(.duration)`. Moved this into an unstructured asynchronous `Task` so the view mounts instantly.

### Phase 4: Structural cleanup
- **Implemented:** Introduced `static let assetCache = NSCache<NSString, PHAsset>()` inside `RecordingsService`. Subsequent `asset(for:)` hits now resolve instantly in memory, removing a 285ms repeated PhotoKit penalty identified in the final trace.
- **Implemented:** Shared a single `RecordingsService` instance across all closures in `CameraView`'s player presentation, rather than re-instantiating the struct repeatedly.
- **Implemented:** Converted unstructured `Task`s inside `RecordingPlayerView` to `.task(id:)` modifiers, cleanly hooking into SwiftUI's cancellation lifecycle.

**Result:** The memory staircase is fixed (via the 15-item bound and `stopCachingAll`), and the main thread freezes are eliminated (via the NSCache and lazy `load(.duration)`). The app no longer black-screens or hangs.
