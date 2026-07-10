July 9, 2026 - GitHub Copilot (Claude Opus 4.7)

# Video Player + Carousel Fix Plan

Scope: `RecordingPlayerView`, `RecordingCarouselView`, and the `CameraView` presentation layer that hosts them.

Non-goals: no changes to `RecordingsService`'s PhotoKit primitives beyond a bounded fetch, no changes to the camera surface, no new UI features.

---

## 1. Problems

1. Delete removes the WRONG recording after the user swipes in the carousel.
2. Playback continues through Close, Share, and Delete taps.
3. Yellow active-cell border drifts when the recordings array changes.
4. Overall lag on Photo Library refresh after save / delete / iCloud sync.
5. Carousel gesture strip is 100pt tall and steals swipes intended for the player.
6. Carousel captures any drag > 5pt with no vertical drop-through, so diagonal or up-swipes near the bottom of the screen never reach the player.

---

## 2. Gesture Audit

Two nested horizontal `DragGesture` recognizers exist:

1. Player pager
   - `RecordingPlayerView.body` -> outer `GeometryReader` -> `.gesture(DragGesture(minimumDistance: 10))`
   - Direction-locks to horizontal only when `abs(dx) > abs(dy) * 1.5` (`PagerConstants.horizontalLockRatio`).
   - Rubber-bands at first/last recording (`rubberBandFactor: 0.15`).

2. Carousel strip
   - `RecordingCarouselView.body` -> inner `GeometryReader` -> `HStack` -> `.gesture(DragGesture(minimumDistance: 5))`.
   - No direction lock; ANY drag over 5pt is stolen by the strip.
   - `.frame(height: cellHeight + Theme.space16)` = 100pt tall (84 cells + 16 padding).
   - `.contentShape(Rectangle())` on the offset HStack, so hit area covers the full 100pt regardless of visible cell scale (0.55 opacity for non-active).

Tap surfaces:

1. Active player: `.onTapGesture { togglePlayPause() }` on `AVPlayerHostingView`.
2. Each carousel cell: `.onTapGesture { onSelect(recording) }`.

Conflict summary:

1. Vertical / diagonal swipes originating in the 100pt strip are captured by the carousel and never reach the player pager, even when the user's intent is a diagonal / vertical swipe.
2. Because the strip's `.contentShape` extends 16pt above the visible cell row, the effective tap area is larger than the visible strip and looks like "dead space."
3. The player pager's own direction-lock at 1.5x is generous, but the strip captures FIRST because SwiftUI resolves nested `.gesture()` calls innermost-first.
4. Result: users describe "the tap/swipe area on the carousel is large" and "the video player and carousel conflict" — both are literally true.

---

## 3. Fixes

Each item lists intent and touchpoints. Full patches produced during implementation.

### Fix A - Delete the currently displayed recording

1. Change `RecordingPlayerView.onDelete` from `() -> Void` to `(Recording) -> Void`.
2. Confirmation dialog Delete button calls `onDelete(activeRecording)`.
3. `CameraView` closure receives the recording and deletes that one; drop the captured `let recordingToDelete = recording` line.
4. `viewModel.refreshLatestRecording()` still runs after; auto-advance in `.onChange(of: recentRecordings)` will fire correctly because the CURRENT active recording is now the one removed from the list.

Files:
1. [PromptCam/Views/Recordings/RecordingPlayerView.swift](../PromptCam/Views/Recordings/RecordingPlayerView.swift)
2. [PromptCam/Views/CameraView.swift](../PromptCam/Views/CameraView.swift)

### Fix B - Pause playback on Close, Share, Delete

1. Add `pausePlayback()` helper in `RecordingPlayerView` that calls `player?.pause()` and sets `isPlaying = false`.
2. Close button: call `pausePlayback()` before `dismiss()`.
3. Delete button: call `pausePlayback()` before `showDeleteConfirmation = true`.
4. Share: attach `.simultaneousGesture(TapGesture().onEnded { pausePlayback() })` to the `ShareLink` label.

Files:
1. [PromptCam/Views/Recordings/RecordingPlayerView.swift](../PromptCam/Views/Recordings/RecordingPlayerView.swift)

### Fix C - Yellow active-cell frame stays centered

1. In `RecordingCarouselView`, add `.onChange(of: recordings)` that recomputes `baseOffset` for the current `activeRecordingID` (index recompute using `firstIndex(where:)`).
2. Also clear `dragOffset = 0` in that handler to drop any stale live-drag translation.
3. Do NOT animate this recentering (it is a data-driven correction, not a user-initiated navigation).

File:
1. [PromptCam/Views/Recordings/RecordingCarouselView.swift](../PromptCam/Views/Recordings/RecordingCarouselView.swift)

### Fix D - Tighten carousel gesture surface

1. Drop `.contentShape(Rectangle())` on the HStack; keep tap targets on each cell.
2. Attach the `DragGesture` to the HStack itself but constrain the gesture-active region via a smaller `.contentShape` sized to `cellHeight` (84pt) instead of the 100pt strip padding.
3. Add a direction lock to the carousel drag so vertical / diagonal swipes fall through to the player pager. Threshold: activate only when `abs(dx) > abs(dy) * 1.2` (looser than the player's 1.5 to preserve carousel responsiveness, but still requires clear horizontal intent).
4. Bump carousel `DragGesture(minimumDistance:)` from 5 to 8 so short taps do not accidentally trigger drag.

File:
1. [PromptCam/Views/Recordings/RecordingCarouselView.swift](../PromptCam/Views/Recordings/RecordingCarouselView.swift)

### Fix E - Reduce refresh lag with bounded fetch

1. In `RecordingsService.fetchAllRecordings()`, add `options.fetchLimit = 200`.
2. `Recording` objects wrap `PHAsset` references; the carousel already only needs recent items. 200 is enough for a scrollable session without paging into the tens of thousands.
3. Document the cap in the function header.

File:
1. [PromptCam/Services/RecordingsService.swift](../PromptCam/Services/RecordingsService.swift)

### Fix F - Small drift guard on live drag during array reorder

1. If `recordings` mutates while a drag is in flight, current code leaves `dragOffset` set relative to the OLD indexing. Add a "cancel active drag" step to Fix C so mid-flight drags are dropped instead of committing to a stale index.

File:
1. [PromptCam/Views/Recordings/RecordingCarouselView.swift](../PromptCam/Views/Recordings/RecordingCarouselView.swift)

---

## 4. Test Plan

Unit tests (added to `PromptCamTests`).

1. `RecordingCarouselCenteringTests.swift` (new)
   1. `testBaseOffsetForActiveIndex` - given `slotWidth = 94`, active index 3 -> `baseOffset == -282`.
   2. `testRecenteringWhenItemBeforeActiveRemoved` - initial active at index 3, remove index 1, active is now at index 2; recomputed `baseOffset == -188`.
   3. `testRecenteringWhenItemInsertedBeforeActive` - initial active at index 2, insert new item at index 0, active is now at index 3; recomputed `baseOffset == -282`.
   4. `testCommitDragChoosesNextOnLeftFlick` - given `velocity = -700`, `translation = -60` -> target = current + 1.
   5. `testCommitDragChoosesPrevOnRightFlick` - given `velocity = +700`, `translation = +60` -> target = current - 1.
   6. `testCommitDragClampsAtEdges` - given active is last index, left flick returns last index.
   7. `testDirectionLockRejectsVerticalDrag` - given `dx = 6, dy = 20` -> gesture should not start (dx/dy = 0.3 < 1.2).
   8. `testDirectionLockAcceptsHorizontalDrag` - given `dx = 40, dy = 8` -> gesture should start (dx/dy = 5.0 > 1.2).

   Approach: extract the drift math and direction-lock predicate into a pure Swift struct (`CarouselDragMath`) so it is testable without SwiftUI. The view keeps the SwiftUI plumbing.

2. `RecordingPlayerActionTests.swift` (new)
   1. `testDeleteCallbackReceivesActiveRecording` - inject a stub `onDelete(Recording) -> Void`; simulate `activeRecording` change; assert callback fires with the CURRENT recording, not the initial one.
   2. `testPausePlaybackClearsIsPlaying` - stub player; call `pausePlayback()`; assert `isPlaying == false`.

   Approach: this requires exposing `pausePlayback()` at file scope OR at least extracting a small `PlayerActions` helper. Prefer extracting a `PlayerActions` reducer with `.pauseIfPlaying(state:) -> PlayerState` so it stays pure.

3. `RecordingsServiceLimitTests.swift` (new)
   1. `testFetchAllRecordingsPassesLimitToOptions` - inject a fake `PHAssetFetcher` protocol; assert `PHFetchOptions.fetchLimit == 200` when `fetchAllRecordings()` is called.

   Approach: this DOES require introducing a small `AssetFetcher` protocol in `RecordingsService`. Recommended only if we want long-term coverage. If we skip this, cover the change with a manual verification note in the PR.

Manual tests (device pass, checklist for PR):

1. Delete correctness
   1. Record A, record B, record C.
   2. Open player (opens on C), swipe to A.
   3. Delete -> confirm.
   4. Expected: A is removed, player auto-advances to B, C is still available.
   5. Repeat with active being B; delete; player should stay on C or advance to the next available.

2. Playback stops on action
   1. Play a video.
   2. Tap Close -> audio stops immediately, no leaked sound during dismiss animation.
   3. Play again -> tap Share -> ShareLink opens; audio stops.
   4. Play again -> tap Delete -> confirmation dialog appears; audio stops.

3. Carousel centering after external changes
   1. Open player, swipe to any active cell not at index 0.
   2. Record a new video from the camera surface behind the player (may need a second device or a scripted trigger).
   3. Expected: carousel re-centers on the still-active cell with no visible drift.
   4. Delete a cell BEFORE the active one from Photos.app.
   5. Expected: carousel re-centers, active cell remains centered.

4. Gesture disambiguation
   1. On the carousel strip, swipe up sharply -> nothing happens on the carousel; player pager should NOT navigate (vertical drag rejected by both).
   2. On the carousel strip, swipe diagonally 45deg down-right -> should NOT trigger carousel navigation (fails 1.2 ratio).
   3. On the carousel strip, swipe purely horizontal -> carousel navigates.
   4. On the video area above the carousel, swipe horizontal -> player pager navigates.
   5. On the video area, tap -> play / pause toggles.

5. Post-delete perceived latency
   1. Save 20+ videos.
   2. Delete one -> observe how long until the removed thumbnail disappears from the carousel.
   3. Expected with Fix E: sub-500ms on a device with 200+ videos in library.

---

## 5. Risks

1. Direction-lock on the carousel may briefly feel less "grippy" for users used to the old 5pt trigger. Mitigated by keeping the threshold at 1.2 (looser than the player's 1.5).
2. `fetchLimit = 100` hides older videos from the carousel. Acceptable because the carousel is UX-designed for RECENT clips; if the user wants full library access, that is `RecordingsLibrarySheet`. <I adjusted this limit to 100 keep that.>
3. Recentering on `recordings` change may look like a jump if the array changes while the user is mid-drag. Fix F cancels the drag to keep the visual clean.

---

## 6. Rollout

1. Feature branch: `fix/recordings-player-and-carousel`.
2. Order of commits (each self-contained if possible):
   1. Fix A + tests.
   2. Fix B + tests.
   3. Fix C + Fix F + tests.
   4. Fix D + tests.
   5. Fix E + test note.
3. Run `xcodebuild ... test` after each commit; full suite must stay green.
4. Squash-merge into `main` under a single PR titled: "fix: recordings player delete, pause-on-action, carousel centering, gesture disambiguation."
5. Manual device pass per Section 4 checklist before merge.

---

## 7. Out of Scope for This Plan

1. Swipe-down-to-dismiss on the player (nice iOS Photos-style gesture, but not a bug fix).
2. Persistent recordings pagination beyond 200 (would require `RecordingsLibrarySheet` rework).
3. Analytics for delete / share / navigation actions.
4. Cover-thumbnail cache across swipes.
