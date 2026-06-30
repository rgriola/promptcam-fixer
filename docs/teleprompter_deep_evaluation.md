# Teleprompter Placement — Deep Evaluation

## The Problem

The script overlay does not correctly accommodate all script sizes. Depending on script length and font size, the text can start in the wrong position, fail to scroll fully off-screen, or get clamped into a range that clips content. Your intuition — that the math is over-complicated and a simpler "always start centered, scroll until gone" model would work — is directionally correct and the analysis below explains exactly why.

---

## File-by-File Review

### 1. [TeleprompterGeometry.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Models/TeleprompterGeometry.swift)

This is the math core. Every offset value the overlay uses ultimately comes from here.

#### What it computes

| Property | Formula | Intent |
|---|---|---|
| `lineHeight` | `fontSize × 1.4` | Approximate single line height. Used to anchor "first line" positions. |
| `startOffset` (= `centerOffset`) | `viewportH/2 − padding − lineH/2` | First line centered vertically in the viewport. |
| `manualEndOffset` | `−(textH − viewportH) − padding + lineH` | Last line sits just above the top edge. |
| `centerOffset` | (same as `startOffset`) | Redundant alias — `startOffset` is literally `centerOffset`. |
| `autoScrollFloor` | `−(textH + padding)` | Script fully exited past the top. |

#### Problems identified

1. **`startOffset` and `centerOffset` are the same value.** The code has `var startOffset: CGFloat { centerOffset }`. This means the "start boundary" IS the center position — there is no separate concept of "starting off-screen below" anymore. The original `teleprompter-fix.md` plan described `startOffset` as "first line below viewport bottom", but the implementation collapsed it into center. This means **the progress range [0, 1] maps from `manualEndOffset` to `centerOffset`**, not from end-to-start-below-bottom. The full travel range is smaller than it should be.

2. **`manualEndOffset` formula is fragile for short scripts.** When `textH < viewportH` (short scripts), `manualEndOffset` becomes _positive_ (pushes content down), which means `manualEndOffset > startOffset` is possible. When that happens, `manualTravel` returns 0, the swipe guard bails out (`guard span > 0`), and **the user cannot reposition the script at all**. More importantly, the offset clamp in the overlay (`min(max(interim, minY), maxY)`) inverts — `minY > maxY` — producing unpredictable snap behavior.

3. **`lineHeight` approximation drifts.** `fontSize × 1.4` is a rough heuristic. The actual rendered line height depends on the font (rounded semibold via `Theme.fontFamily`), line spacing, and dynamic type. A 10-15% error here shifts `centerOffset` by 3–6 pt on a typical device, causing the "centered" start to visibly miss the mark on larger font sizes.

4. **`autoScrollFloor` ignores the viewport entirely.** It's `−(textH + padding)`, which means the floor is always `textH` points above the origin regardless of where the viewport is or how tall it is. For a very short script with a tall viewport, the floor is only slightly negative while `startOffset` (center) is a large positive number — so the script barely moves before hitting the floor.

---

### 2. [TeleprompterOverlayView.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/TeleprompterOverlayView.swift)

This is the rendering + animation layer. It has **two independent offset pipelines** that don't talk to each other cleanly:

#### Pipeline A — TimelineView body (lines 72-92)

```
baseOffset = geometry.startOffset          // = centerOffset
autoOffset = isScrolling ? −elapsed×speed : 0
interim    = baseOffset + manualOffset + dragTranslationY + autoOffset
totalY     = clamp(interim, minY=manualEndOffset, maxY=baseOffset)
```

This pipeline drives the **actual rendered position** every frame.

#### Pipeline B — `currentOffset(at:)` (lines 215-219)

```
guard isScrolling else { return pausedOffset }
return max(autoScrollFloor, scrollStartOffset − elapsed × speed)
```

This pipeline is used **only by the debug HUD**. It's a completely separate calculation with its own floor and its own notion of start offset. It doesn't use `manualOffset` or `dragTranslationY` at all.

> [!WARNING]
> **Pipeline A clamps to `manualEndOffset`; Pipeline B clamps to `autoScrollFloor`.** During auto-scroll, Pipeline A will stop the text at `manualEndOffset` (last line at top edge), never letting it scroll off screen. The `autoScrollFloor` that was supposed to let the script exit past the top **is never used by the actual rendering pipeline**. It's only referenced in the dead-code `currentOffset(at:)` path.

#### Other issues

- **`startOffsetProgress` is accepted as a prop but never used to compute the offset in Pipeline A.** The `baseOffset` is always `geometry.startOffset` (center). The `startOffsetProgress` only triggers `resetScrollPosition()` via `.onChange`, which resets `pausedOffset`, `scrollStartOffset`, and `scrollStartTime` to zero — it doesn't actually change where the text sits. The initial position is determined by `manualOffset`, which is only changed by drag gestures and the bake-in on scroll stop.

- **`resetScrollPosition()` zeroes everything** including the auto-scroll timer, but `manualOffset` survives. So if the user had swiped the text, that swipe offset persists through a reset — the reset isn't really a reset.

- **`handleScrollStateChanged`** bakes the auto-scroll distance into `manualOffset` when stopping. This is correct for pause/resume continuity, but combined with the clamping in Pipeline A, it means `manualOffset` accumulates a value that may exceed the clamp range, creating a "stuck" state where the next play/stop cycle bakes in even more offset.

---

### 3. [TeleprompterConfig.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Models/TeleprompterConfig.swift)

This is the simplest file and has the fewest issues:

- `startOffsetProgress` defaults to `1.0` and is explicitly unclamped (comment on line 23). The CameraView auto-centers it to `geometry.centerProgress` on text change, which is approximately `1.0` since `startOffset == centerOffset`. So the progress value is basically always near 1.0 and doesn't contribute meaningful state.

- The field is a vestige of the old lane-based UI. With the lane gated off, `startOffsetProgress` flows through CameraView → OverlayView → `.onChange` → `resetScrollPosition()`, but as noted above, that path doesn't actually set the rendered position.

---

## Root Cause Summary

The placement bug has **three interacting root causes**:

1. **The auto-scroll floor (`autoScrollFloor`) is computed but never applied to the rendering pipeline.** Pipeline A clamps to `manualEndOffset`, so the script physically cannot scroll past the last-line-at-top position during playback. The text never rolls off screen.

2. **Short-script geometry inverts.** When `textH < viewportH`, `manualEndOffset` crosses above `startOffset`, making `minY > maxY`. The clamp produces an unpredictable snap and the swipe span becomes 0.

3. **`startOffsetProgress` is a no-op in the rendering path.** The progress-to-offset conversion exists in `TeleprompterGeometry.offset(forProgress:)` but Pipeline A never calls it. The actual position is `centerOffset + manualOffset + drag + auto`, bypassing progress entirely.

---

## Fix Options

### Option A: Your Proposal — "Center Start, No Endpoint, Infinite Scroll-Off"

**Concept:** Remove all endpoint math. The script always starts with its first line vertically centered. Auto-scroll subtracts from that offset indefinitely (no floor clamp) until the _last_ line has exited past the top of the viewport, then stops.

**How it would work in `TeleprompterGeometry`:**

- **Keep:** `centerOffset` (as `startOffset`). No change.
- **Remove:** `manualEndOffset`, `manualTravel`, `offset(forProgress:)`, `progress(forOffset:)`, `centerProgress`.
- **Change:** `autoScrollFloor` = `−(textH + padding)` — keep this but **actually use it** as the clamp in Pipeline A.
- **Add:** a simple `scrollStopOffset` = `−textH` (the point at which the last line clears the top edge).

**In `TeleprompterOverlayView` Pipeline A:**

```
baseOffset = geometry.startOffset     // centerOffset, unchanged
autoOffset = isScrolling ? −elapsed × speed : 0
interim    = baseOffset + manualOffset + dragTranslationY + autoOffset
totalY     = max(interim, geometry.scrollStopOffset)  // only a FLOOR, no ceiling
```

No `maxY` ceiling clamp needed because you never want to prevent the user from dragging the text up manually — the only constraint is "don't scroll past the point where the last line is gone."

**Pros:**
- Dramatically simpler. One start point, one stop point, one direction.
- Works identically for 1-line and 1000-line scripts.
- No progress normalization, no span calculation, no inverted-range bugs.
- The `startOffsetProgress` field, the progress↔offset conversion functions, and the entire `manualEndOffset` concept can be deleted.

**Cons:**
- Manual swipe repositioning needs a different clamp. Without `manualEndOffset` as a ceiling, you'd need a practical upper bound (e.g., don't let the user drag the first line below the viewport bottom edge) to prevent dragging text off-screen downward.
- The reset button becomes trivial (snap to `centerOffset`, set `manualOffset = 0`) — this is actually a pro, just noting the simplification.

> [!TIP]
> **This is the cleanest option.** It eliminates the most code and the most failure modes. The only new thing you'd need to define is a sensible upper clamp for manual dragging (first line can't go below viewport bottom).

---

### Option B: Fix Pipeline A to Use `autoScrollFloor` + Fix Short-Script Inversion

**Concept:** Keep the existing architecture but fix the two specific bugs: (1) use `autoScrollFloor` as the floor in Pipeline A during auto-scroll, and (2) handle the `textH < viewportH` case in `manualEndOffset`.

**Changes:**

- In Pipeline A, use `autoScrollFloor` as `minY` when `isScrolling`, and `manualEndOffset` as `minY` when paused.
- Guard `manualEndOffset`: when `textH ≤ viewportH`, return `startOffset` (text stays centered, no scroll needed).
- Keep `startOffsetProgress` and the progress conversion functions.

**Pros:**
- Smallest diff. Fixes the immediate bugs without restructuring.
- Preserves progress-based positioning for future features (e.g., if you bring back a slider).

**Cons:**
- Doesn't address the fundamental complexity. `startOffsetProgress` is still a vestigial no-op in the rendering path. Two pipelines still exist. The `lineHeight` approximation still drifts.
- You're patching around the architecture rather than simplifying it.

---

### Option C: Hybrid — Center Start + Retained Manual Range for Swipe

**Concept:** Start position is always centered (like Option A), but retain a `manualEndOffset` purely as a swipe clamp so the user can drag the text up to see the end, but not past it.

**Changes:**

- `startOffset` = `centerOffset` (same as now).
- `manualEndOffset` stays but is only used as a swipe floor, never as a scroll-stop floor.
- Auto-scroll uses `scrollStopOffset = −textH` (like Option A).
- Remove `startOffsetProgress` and all progress conversion.
- For short scripts (`textH < viewportH`), `manualEndOffset` = `startOffset` (no swipe travel, text stays centered).

**Pros:**
- Gets the simplicity of Option A for the auto-scroll path.
- Gives swipe a well-defined range so the user can preview end-of-script but can't drag text into nonsensical positions.

**Cons:**
- Slightly more complex than Option A. You still have two clamp values (swipe floor vs. auto-scroll floor).
- The `manualEndOffset` name and concept survive, even though it means something different now (swipe limit, not scroll stop).

---

## Recommendation

| Criteria | Option A | Option B | Option C |
|---|---|---|---|
| Fixes all scripts | ✅ | ✅ | ✅ |
| Simplicity | ⭐⭐⭐ | ⭐ | ⭐⭐ |
| Code removed | ~40 lines | ~5 lines | ~25 lines |
| Risk of new bugs | Low | Medium (patching) | Low |
| Future flexibility | Good | Best (keeps progress) | Good |

**Option A is the strongest choice.** Your instinct to eliminate the endpoint math is correct — the current architecture has too many interacting concerns for the simple behavior you want. The `startOffsetProgress` normalized range adds no value since the lane is disabled and the rendering pipeline ignores it anyway.

The one thing to define for Option A is the **manual drag upper bound**: I'd suggest `viewportH − lineH` (first line can't go lower than one line-height above the viewport bottom edge). This gives a natural "you can always see the first line" constraint without any of the existing span/progress machinery.

---

## Dead Code to Clean Up (Any Option)

Regardless of which option you choose, these are safe to remove:

- `currentOffset(at:)` in OverlayView — only used by debug HUD, and computes a value that doesn't match what's actually rendered
- `offsetForProgress(_:)` in OverlayView — wrapper that just calls geometry, never called from Pipeline A
- `autoScrollFloor()` function in OverlayView — wrapper, same
- `TeleprompterTextHeightPreferenceKey` — the PreferenceKey struct at bottom of OverlayView is never used (measurement is done via UIKit `boundingRect` and GeometryReader `.onAppear`/`.onChange`)
- `pausedOffset` state — set to 0 in `resetScrollPosition` but never read by Pipeline A
- `scrollStartOffset` state — set to 0 in `resetScrollPosition`, used in `handleScrollStateChanged` but Pipeline A computes its own offset chain

