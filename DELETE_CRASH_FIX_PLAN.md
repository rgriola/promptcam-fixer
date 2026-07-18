# Recording Delete Crash — Fix Plan

**Branch**: `fix/recording-delete-crash` (to be created off `main`)  
**Priority**: Ship-blocking — crashes on user delete flow  
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
