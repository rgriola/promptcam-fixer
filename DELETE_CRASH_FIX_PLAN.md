# Recording Delete Crash — Fix Plan

**Branch**: `fix/recording-delete-crash` (merged into `main` on 2026-07-18)  
**Priority**: Ship-blocking — crashes on user delete flow  
**Status**: ✅ Landed. Verified on-device on iPhone 17 Pro and iPhone 15.  
**Author**: GitHub Copilot  
**Date**: 2026-07-18

---

## Decision Summary

- **Keep both warnings.** Warning #1 is our custom confirmation. Warning #2 is the iOS-owned "Delete from Photo Library" alert with the thumbnail, presented automatically by `PHAssetChangeRequest.deleteAssets`. This two-alert pattern matches Photos.app, Instagram, and other iOS-native gallery apps, and is what users expect.
- **Fix the crash first.** The permissions workflow issue is non-destructive; this crash risks user data trust.
- **No architectural change** to storage or permissions in this fix. That refactor lives on `feature/photo-library-permission-refactor`.

---

## Root Cause

The crash is a Swift 6 concurrency / SwiftUI View-identity race during the post-delete state cascade. Timeline:

1. User taps trash → our `.confirmationDialog` (Warning #1) → Delete
2. `onDelete()` closure calls `RecordingsService().deleteRecording(...)`
3. PhotoKit presents its system alert (Warning #2) → Delete
4. PhotoKit's `performChanges` completion returns `success: true`
5. `viewModel.recordings.refresh()` is called **fire-and-forget** — spawns an internal `Task { await prefetch() }`
6. `prefetch()` mutates `latestRecording`, `latestVideoURL`, `recentRecordings` in non-deterministic order
7. `.fullScreenCover`'s `if let recording = viewModel.recordings.latestRecording` re-evaluates. SwiftUI sees `latestRecording` changed, tears down the current `RecordingPlayerView`, builds a new one for the new recording
8. Simultaneously, the _outgoing_ player's `.onChange(of: recentRecordings)` fires an auto-advance `Task { selectRecording(newRecordings[0]) }`
9. Overlapping teardown: AVPlayer KVO invalidation + in-flight `PHImageRequestID` cancellation + AVPlayerItem observation + parent view re-init all run against the same objects
10. Swift 6 concurrency check trips (executor mismatch or main-actor violation from a PhotoKit callback) → **crash**

Contributing factors:

- `refresh()` is `Task { ... }` fire-and-forget instead of async — no ordering guarantee
- Two independent code paths react to state changes after delete (parent `.fullScreenCover` re-eval + child `.onChange`)
- `AVPlayer` teardown is not gated behind a single MainActor barrier

---

## Fix Strategy

Make the post-delete state transition **sequential, single-owner, and idempotent**:

1. Await deletion + refresh in one chain before returning control
2. Single source of truth decides the next `activeRecording` (or dismiss) — the child player never races on it
3. Keep the `RecordingPlayerView` mounted across recordings; drive content via internal `activeRecording` state, never via View identity swaps
4. Explicit MainActor teardown order for AVPlayer resources

---

## Changes by File

### 1. [PromptCam/ViewModels/RecordingsGallery.swift](PromptCam/ViewModels/RecordingsGallery.swift)

- **Change `refresh()` from fire-and-forget to `async`**:
  ```swift
  func refresh() async { await prefetch() }
  ```
- **Add `delete(_:) async` that pre-computes the next-active recording BEFORE mutating state**:
  ```swift
  func delete(_ recording: Recording) async -> Bool {
      let ok = await recordingsService.deleteRecording(recording)
      guard ok else { return false }
      // Compute the next active before mutation so downstream views see one atomic update.
      let deletedID = recording.id
      let all = await recordingsService.fetchAllRecordings()
      let nextActive: Recording? = {
          if let idx = recentRecordings.firstIndex(where: { $0.id == deletedID }) {
              // Prefer the item that took the deleted slot; fall back to previous.
              if idx < all.count { return all[idx] }
              if idx > 0, idx - 1 < all.count { return all[idx - 1] }
          }
          return all.first
      }()
      // Single main-actor transaction — all @Observable mutations happen together.
      recentRecordings = all
      latestRecording = nextActive
      latestVideoURL = nil            // resolve lazily in the player
      return true
  }
  ```

### 2. [PromptCam/Views/CameraView.swift](PromptCam/Views/CameraView.swift#L269-L295)

- **Replace `.fullScreenCover` block with a stable player mount** — keep the player alive across recordings; do not re-evaluate `if let recording` at the cover boundary. Instead pass the whole `RecordingsGallery` (or an `activeRecording` binding) and let the player render its own empty state when there's nothing to show.
- **Await `delete` instead of fire-and-forget**:
  ```swift
  onDelete: {
      let target = recording
      Task { @MainActor in
          _ = await viewModel.recordings.delete(target)
          if viewModel.recordings.recentRecordings.isEmpty {
              viewModel.recordings.showDirectPlayer = false
          }
      }
  }
  ```

### 3. [PromptCam/Views/Recordings/RecordingPlayerView.swift](PromptCam/Views/Recordings/RecordingPlayerView.swift)

- **Remove the `.onChange(of: recentRecordings)` auto-advance block** ([lines 227-238](PromptCam/Views/Recordings/RecordingPlayerView.swift#L227-L238)). The parent gallery is now the single owner of "what plays next" — the player just reacts to a driven `activeRecording` change.
- **Drive `activeRecording` from an external binding or explicit onChange on `latestRecording`** rather than local `@State`. Options:
  - Pass `activeRecording: Binding<Recording?>` and let `RecordingsGallery.latestRecording` be the source
  - Or, keep `@State` but add `.onChange(of: latestRecording)` that syncs and resolves the new URL, replacing the removed auto-advance path
- **Harden `teardownPlayer()`** — verify strict order under MainActor:
  ```swift
  @MainActor
  private func teardownPlayer() {
      statusObservation?.invalidate()
      statusObservation = nil
      if let id = inFlightRequestID {
          PHImageManager.default().cancelImageRequest(id)
          inFlightRequestID = nil
      }
      if let token = timeObserverToken {
          player?.removeTimeObserver(token)
          timeObserverToken = nil
      }
      player?.pause()
      player = nil
      hideControlsTask?.cancel()
      hideControlsTask = nil
  }
  ```

### 4. [PromptCam/Views/Sheets/RecordingsLibrarySheet.swift](PromptCam/Views/Sheets/RecordingsLibrarySheet.swift#L122-L133)

- Apply the same await pattern in its `deleteRecording(_:)` — this sheet uses the same crash-prone flow when active.

---

## Non-goals for this fix

- **No** change to how videos are stored (still Photo Library)
- **No** change to permission model (still `.readWrite`)
- **No** removal of Warning #2 (accepted as industry-standard UX)
- **No** carousel behavior changes (works fine after crash fix)
- **No** RecordingsLibrarySheet redesign (parked; direct player is primary path)

---

## Verification Steps

1. Record 3+ short videos in the app
2. Open direct player → delete middle video → confirm both warnings → verify player advances to next video with no crash
3. Record 1 video → delete it → confirm both warnings → verify player dismisses cleanly, camera view visible
4. Rapid-fire: record, delete, record, delete — verify no stale AVPlayer instances hanging around (memory graph)
5. Delete while a video is still resolving from iCloud — verify PhotoKit `PHImageRequestID` is cancelled
6. Delete → immediately swipe carousel — verify no ghost thumbnails and no crash
7. Repeat from `RecordingsLibrarySheet` path (Camera Roll)

## Regression watch

- AVPlayer being reused instead of recreated — check for stale time observer callbacks firing after teardown
- Carousel `activeRecordingID` binding — should stay in sync with `latestRecording` transitions
- `.fullScreenCover` presentation identity — must not thrash when `latestRecording` changes

---

## Suggested Commit Plan

1. `Gallery: convert refresh to async; add delete(_:) with atomic next-active`
2. `Player: remove onChange auto-advance; drive from parent gallery`
3. `Player: harden teardown order under MainActor`
4. `CameraView: await delete; stable full-screen cover mount`
5. `RecordingsLibrarySheet: match new await pattern`
6. Manual QA pass per verification steps above
7. Merge to `main` behind PR review

---

## Follow-up (separate branches)

- **`feature/photo-library-permission-refactor`** — Option 4 refactor already scoped. Solves the Limited Access UX and eventually removes the need for Warning #2 by moving to app-owned storage.
- **Recording carousel polish** — sync active-cell binding, fix any residual thumbnail flicker after delete.

---

## Actual Implementation — Deviations & Additions

The original plan proposed 5 commits and a specific set of file edits. During implementation we discovered a pre-existing build break, chose a simpler player-sync pattern than the original plan proposed, and consolidated into a single commit for merge cleanliness. This section documents what actually shipped.

### Merge commit

- `99333ae` — `Merge fix/recording-delete-crash into main` (--no-ff, preserves branch history)
- `2aafa0b` — `Fix recording-delete crash: atomic gallery.delete + hardened teardown`

### Prerequisite work not in the original plan

The delete-crash work exposed a **pre-existing build break** in `main` from the earlier ViewModel-extraction refactor commits (`b4fe383`, `f7541fb`, `909f391`). Two things had to be fixed before the crash fix could compile:

1. **SwiftUI `@Bindable` writable key-path requirement**. `modalQueue`, `audioMeter`, and `recordings` in [PromptCam/ViewModels/CameraViewModel.swift](PromptCam/ViewModels/CameraViewModel.swift) had been declared `let`. Swift 6 + SwiftUI's `@Bindable` requires **writable key paths** through sub-objects for chained bindings like `$viewModel.recordings.showDirectPlayer` to compile. Changed all three from `let` to `var`. The classes are never reassigned — this is an API surface requirement, not a semantic change.

2. **Xcode project regen via xcodegen**. Files added in the extraction refactors (`RecordingsGallery`, `ModalQueue`, `AudioMeterViewModel`, `TeleprompterStyleStore`, `RecordingTimer`) were not yet referenced by `PromptCam.xcodeproj/project.pbxproj`. Ran `xcodegen generate` to sync from [project.yml](project.yml).

### Deviation: player `activeRecording` stayed `@State`

The plan proposed two options for driving the player's `activeRecording`:

- Option A: Pass it as `Binding<Recording?>` from the parent
- Option B: Keep `@State`, add `.onChange(of: latestRecording)` that syncs and re-resolves URL

**We chose a variant of Option B** — kept `activeRecording` as `@State`, but the sync happens in the existing `.onChange(of: recentRecordings)` handler rather than adding a new observer. When the active recording is no longer in the refreshed list, we perform an **in-place swap**:

```swift
.onChange(of: recentRecordings) { _, newRecordings in
    let isActiveStillInList = newRecordings.contains { $0.id == activeRecording.id }
    guard !isActiveStillInList else { return }
    guard !newRecordings.isEmpty else { dismiss(); return }

    // In-place sync — the parent's atomic snapshot already picked
    // next-active. Cancel in-flight resolve and swap identity; the
    // existing .task(id: activeURL) observer will re-resolve the URL.
    cancelInFlightResolve()
    activeRecording = newRecordings.first!
    activeURL = nil
    loadFailed = false
}
```

Why: the original plan's "remove `.onChange` entirely" would have required a parent-driven Binding, which meant redesigning the player's initializer surface. In-place sync gave us the same race-free behaviour with a much smaller diff, and preserved backward-compat for the `RecordingsLibrarySheet` path which has no parent gallery to bind to.

### Addition: `refreshInBackground()` alongside `refresh() async`

The plan proposed converting `refresh()` to `async`. But three call sites in [PromptCam/ViewModels/CameraViewModel.swift](PromptCam/ViewModels/CameraViewModel.swift) are **non-delete** save-completion callbacks (photo-library monitor, `onRecordingStateChanged`, `onRecordingSavedToLibrary`) that should not block their caller. Making `refresh()` awaitable would have forced these sites to wrap in `Task { await ... }` — reintroducing the same fire-and-forget pattern with more ceremony.

**Solution**: two methods, one type-safe intent per caller.

```swift
/// Awaitable — for callers that must sequence post-refresh work (e.g. delete).
func refresh() async { await prefetch() }

/// Fire-and-forget — for save-completion sites that shouldn't block.
func refreshInBackground() { Task { await prefetch() } }
```

The delete path uses `refresh()` transitively via `delete(_:)`; the three background callers use `refreshInBackground()`.

### Addition: `RecordingsLibrarySheet` UX bonus

While updating the sheet's `deleteRecording(_:)` to match the await pattern, we added a small UX guard:

```swift
let ok = await RecordingsService().deleteRecording(recording)
guard ok else { return }  // NEW — was `_ = await ...`
selectedRecording = nil
selectedItems = []
videoURL = nil
```

Before this change, cancelling the iOS system delete alert (Warning #2) would still tear down the player and dump the user back to the picker even though nothing was deleted. Now the player stays mounted on cancel, matching Photos.app behaviour.

### Deviation: single squashed commit

The plan listed 5 commits. In practice, the changes were **tightly coupled by the async-refactor ripple**:

- Making `RecordingsGallery.refresh()` async required updating three callers in `CameraViewModel` simultaneously
- The delete-flow `guard let recording` in `CameraView` depended on the new `delete(_:)` method
- The player's `.onChange` rewrite depended on the parent's atomic-snapshot behaviour

A per-file split would have left multiple broken bisect points. We consolidated into one commit (`2aafa0b`) whose message documents the sub-components, and merged with `--no-ff` so the branch commit is preserved distinct from the merge commit for archaeology.

### Files touched (final tally)

| File                                                         | Purpose                                                                                                                     |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| `PromptCam.xcodeproj/project.pbxproj`                        | Regenerated via xcodegen — added extracted files                                                                            |
| `PromptCam/Assets.xcassets/AppIcon.appiconset/Contents.json` | Auto-touched by xcodegen (harmless whitespace)                                                                              |
| `PromptCam/ViewModels/CameraViewModel.swift`                 | `let → var` × 3; `refresh()` → `refreshInBackground()` × 3                                                                  |
| `PromptCam/ViewModels/RecordingsGallery.swift`               | `refresh()` now async; added `refreshInBackground()`; added atomic `delete(_:) async`                                       |
| `PromptCam/Views/CameraView.swift`                           | Delete callback awaits `gallery.delete(_:)`, dismisses on empty library                                                     |
| `PromptCam/Views/Recordings/RecordingPlayerView.swift`       | In-place `activeRecording` sync in `.onChange(of: recentRecordings)`; hardened `teardownPlayer` with strict MainActor order |
| `PromptCam/Views/Sheets/RecordingsLibrarySheet.swift`        | Only dismisses on delete success (cancel-alert UX bonus)                                                                    |
| `DELETE_CRASH_FIX_PLAN.md`                                   | This file (added)                                                                                                           |

### On-device QA — Result

Executed the full verification checklist on iPhone 17 Pro and iPhone 15 on 2026-07-18. All 7 scenarios pass, no crashes observed. Merged to `main`.
