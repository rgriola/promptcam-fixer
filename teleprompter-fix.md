May 31, 2026 - 10:05pm - GitHub Copilot (GPT-5.3-Codex)

# Teleprompter Fix Plan

## Readback

You want to replace the current manual start-position lane with a direct on-screen interaction model:

- Hide and disable the current manual scroll bar UI for setting script start point.
- Let the user swipe up and down directly on the teleprompter area to shift script position.
- Keep scroll travel endpoints strict:
  - Start boundary: first line sits just below the teleprompter viewport bottom edge.
  - End boundary: last line sits just above the teleprompter viewport top edge.
- Add one mid-screen button where the old manual lane was.
- That button should reset script position so the first line is aligned to the viewport center midpoint.
- Play and pause must continue to work as expected:
  - Resume from the current adjusted position.
  - Continue scrolling until the top-end boundary is reached.

## Current Implementation Review

Current teleprompter behavior is already close to your target and has solid foundations:

- CameraView currently renders TeleprompterOverlayView and a right-side TeleprompterStartOffsetLane.
- TeleprompterOverlayView already supports:
  - Measured text height.
  - Progress-to-offset mapping.
  - Auto-scroll floor to allow full script exit past top.
  - Pause and resume continuity.
- CameraViewModel already stores and clamps startOffsetProgress.

Main gap versus your new direction:

- Positioning is driven by right-side lane drag, not direct swipe on script area.
- There is no dedicated center-reset button for quick repositioning.

## Implementation Plan

## Phase 1: Replace Input Model (Lane Off, Swipe On)

1. Gate the manual lane behind a `kManualLaneEnabled = false` flag in CameraView and skip rendering. Keep `TeleprompterStartOffsetLane` struct in file for now; delete in a later cleanup pass once swipe is validated.
2. Make `TeleprompterOverlayView` hit-testing enabled on the viewport rect only (currently `.allowsHitTesting(false)` in CameraView). Camera preview tap/long-press continue to own the rest of the preview.
3. Add a vertical drag gesture on the teleprompter viewport rect:
   - Use `DragGesture(minimumDistance: 8)` so short taps inside the rect fall through to the preview tap (focus) when feasible. If SwiftUI gesture priority forces a tradeoff, accept that taps inside the teleprompter rect won't trigger focus.
   - Drag delta converts to a script-offset delta in real time, clamped to legal range (see Phase 3).
   - While scrolling: swipe input is ignored (no auto-pause). User must pause first to reposition.

Deliverable:

- Manual lane no longer rendered (still in source, gated off).
- Script can be shifted by direct touch drag on the viewport while paused.
- Camera tap/focus behavior outside the viewport is unchanged.

## Phase 2: Add Mid-Screen Reset Button

1. Add one button at the previous lane position (mid-right side, vertically centered on the teleprompter viewport).
2. Button action sets script to the center-start preset, defined in offset terms (not via the existing 0..1 progress curve):
   - Target offset = `viewportHeight/2 - lineHeight/2 - topPadding` so the first line of script is vertically centered in the viewport.
   - Implemented as a named preset on the offset contract (Phase 3), not a magic number in the button handler.
3. Visibility: button stays visible in both paused and scrolling states. Disabled (dimmed) while recording to avoid accidental jump on camera.
4. If tapped while scrolling: immediately pause, snap to center preset, remain paused.

Deliverable:

- Single reset control is present, predictable, and safe during recording.

## Phase 3: Extend Offset Contract for Swipe + Center Preset

The offset contract already exists in `TeleprompterOverlayView` (`offsetForProgress`, `autoScrollFloor`). This phase extends it, not replaces it.

1. Extract the pure math into a `TeleprompterGeometry` struct (inputs: viewportHeight, textHeight, fontSize, padding) so it is unit-testable outside SwiftUI. Methods:
   - `startOffset()` — first line below viewport bottom (manual start boundary).
   - `manualEndOffset()` — last line above viewport top (manual end boundary, used by swipe clamp).
   - `centerOffset()` — first line vertically centered in viewport (used by reset button).
   - `autoScrollFloor()` — script fully exited past top (used only during autoplay).
2. Drag handler converts swipe delta to a new offset and clamps to `[manualEndOffset, startOffset]`.
3. Reset button writes `centerOffset()`.
4. Autoplay continues to use `autoScrollFloor()` as the lower bound (script may exit past top during scroll — preserved behavior, not a regression).
5. Replace the existing `startOffsetProgress` (0..1) state path with a direct offset value in `TeleprompterConfig`, since swipe and reset both produce offsets, not progress fractions. Migrate or remove `startOffsetProgress` accordingly.

Deliverable:

- One geometry source of truth, reusable by drag, reset button, and autoplay.
- Manual clamp and autoplay floor are intentionally different and documented.

## Phase 4: Play and Pause Continuity Validation

1. Verify pause captures exact current offset.
2. Verify resume continues from captured offset without jump.
3. Verify end-of-script behavior:
   - Stops at top endpoint.
   - Does not overshoot or loop unexpectedly.

Deliverable:

- Predictable and stable play/pause behavior from any swipe-set position.

## Phase 5: Tests and QA Pass

1. Unit tests against `TeleprompterGeometry` (extracted in Phase 3):
   - `startOffset` places first line just below viewport bottom.
   - `manualEndOffset` places last line just above viewport top.
   - `centerOffset` places first line at viewport vertical midpoint.
   - `autoScrollFloor` allows full script exit past top.
   - Swipe-delta clamp respects `[manualEndOffset, startOffset]`.
2. `TeleprompterConfig` tests updated for the new offset field (or removal of `startOffsetProgress`).
3. Manual QA on device:
   - Short script and long script.
   - Large and small font sizes.
   - Pause, swipe, play, pause loops.
   - Reset button from start, mid-scroll (paused), and during recording (disabled state).
   - Orientation and safe-area edge checks.
4. Turn off the diagnostic HUD: set `kTeleprompterDebugHUD = false` in `TeleprompterOverlayView.swift` before sign-off.

Deliverable:

- Verified behavior across real usage paths with diagnostics disabled.

## Acceptance Criteria

- No manual lane is shown on screen (code retained but gated off).
- User can reposition script by direct vertical swipe on the viewport while paused.
- Swipe is ignored while scrolling; user must pause to reposition.
- Reset button is visible at mid-screen lane position, disabled during recording, and snaps the first line to viewport vertical center.
- Scroll starts and resumes from current offset without jump.
- Autoplay continues past the manual top boundary and stops cleanly at the autoplay floor (script fully off-screen top).
- Camera tap-to-focus and long-press AE/AF lock still work outside the teleprompter viewport rect.
- Debug HUD is disabled.
- No jitter, jumps, or position drift after repeated play/pause/swipe cycles.

## Suggested File Touch List

- PromptCam/Views/CameraView.swift
- PromptCam/Views/TeleprompterOverlayView.swift
- PromptCam/ViewModels/CameraViewModel.swift
- PromptCam/Models/TeleprompterConfig.swift
- PromptCamTests/TeleprompterConfigTests.swift

## Execution Order

Phase 3 (geometry extraction) is done first so Phases 1 and 2 build on the same offset contract.

1. Phase 3 — extract `TeleprompterGeometry` and migrate existing offset math.
2. Phase 1 — gate lane off, add swipe gesture on the viewport rect.
3. Phase 2 — add center-reset button.
4. Phase 4 — verify play/pause continuity end-to-end.
5. Phase 5 — tests, QA pass, disable debug HUD.

## Open Decisions (confirm before coding)

A. Yes this is better:

- Swipe-while-scrolling: **ignore** (current plan). Alternative: auto-pause on swipe. Default = ignore.

A. Yes this is fine.

- Reset button during recording: **disabled/dimmed** (current plan). Alternative: active. Default = disabled.

A. The focus issue is real I experienced this while testing. Lets accept this tradeoff for now.

- Tap inside teleprompter rect: may no longer trigger camera focus due to gesture ownership. Acceptable tradeoff for swipe reliability.
