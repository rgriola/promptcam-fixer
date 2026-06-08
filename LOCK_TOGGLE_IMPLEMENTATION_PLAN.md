# AF/AE Lock Toggle Button Implementation Plan

**Created:** June 7, 2026  
**Agent:** GitHub Copilot (Claude Sonnet 4.6)

## Overview

Convert `CameraLockStatusBadgeView` from a passive status indicator into an active toggle button, and simplify the focus indicator from a complex corner-bracket box to a thin yellow rectangle (matching iOS Camera app behavior). This resolves teleprompter layer interference with the long-press lock gesture.

---

## Problem Statement

### Current Issues

1. **Teleprompter Interference:** The teleprompter overlay layer blocks long-press gestures on the camera preview, making AF/AE lock unreliable.

2. **Complex Focus Indicator:** `FocusIndicatorView` shows:
   - Corner brackets (84×84pt yellow box)
   - Vertical EV slider rail
   - Sun icon + EV value label
   - Drag gesture for exposure adjustment

   This is visually heavy and conflicts with the new dedicated EV adjustment panel.

3. **Gesture Confusion:** Users must:
   - Tap to focus
   - Long-press to lock (unreliable with teleprompter)
   - Drag the focus box to adjust exposure

   Too many overlapping gestures in one area.

### Proposed Solution

1. **Lock Toggle Button:** Convert center header badge into a tappable button
   - One tap: Lock AF/AE at current camera state
   - Tap again: Unlock (return to Auto)
   - Visual feedback: "AUTO" (green) ↔ "AE/AF LOCK" (yellow)

2. **Simplified Focus Indicator:** Thin yellow rectangle (like iOS Camera)
   - Shows focus point after tap
   - Auto-fades after 3 seconds
   - No EV slider (moved to dedicated panel)
   - No corner brackets

3. **Gesture Simplification:**
   - Tap preview: Focus at point
   - Tap lock button: Toggle lock state
   - Tap EV button: Adjust exposure via dedicated panel
   - **Remove:** Long-press lock gesture (conflicts with teleprompter)

---

## Current State Analysis

### Existing Components

1. **CameraLockStatusBadgeView** — `CameraTopControlsView.swift` (line 69)
   - Passive text label showing current lock status
   - Green "AUTO" | Yellow "AE/AF LOCK" | Yellow "AE LOCK" | etc.
   - No tap interaction

2. **FocusIndicatorView** — `FocusIndicatorView.swift`
   - 84×84pt corner-bracket box
   - Vertical EV slider rail (110pt tall)
   - Sun icon + EV label that moves with bias
   - Drag gesture for exposure adjustment
   - Positioned at tap/long-press location

3. **Lock Gesture Flow** — `CameraView.swift`
   - **Tap:** `handlePreviewTap()` → unlocks if locked, focuses at point
   - **Long-press:** `handlePreviewLongPress()` → attempts lock at point
   - Calls `viewModel.lockFocusExposure(at:)` or `viewModel.unlockFocusExposure()`

4. **Lock State** — `CameraViewModel.swift`
   - `@Published var lockStatus: CameraLockStatus = .auto`
   - Enum: `.auto`, `.aeAfLocked`, `.aeLocked`, `.afLocked`, `.unsupported`
   - Methods: `lockFocusExposure(at:)`, `unlockFocusExposure()`

---

## Implementation Plan

### Phase 1: Convert Badge to Toggle Button

**File:** `PromptCam/Views/Camera/CameraLockStatusBadgeView.swift`

#### Add Button Wrapper

```swift
struct CameraLockStatusBadgeView: View {
    let status: CameraLockStatus
    let onToggle: () -> Void  // NEW: Callback for button tap

    private var statusColor: Color {
        switch status {
        case .auto:
            return Theme.green
        case .unsupported:
            return Theme.yellow
        case .aeAfLocked, .aeLocked, .afLocked:
            return Theme.yellow
        }
    }

    var body: some View {
        Button(action: onToggle) {
            Text(status.text)
                .font(Theme.mono16Medium)
                .foregroundStyle(statusColor)
        }
        .disabled(status == .unsupported)  // Disable if device doesn't support lock
        .accessibilityLabel("Focus and exposure lock")
        .accessibilityHint(status.isLocked ? "Tap to unlock" : "Tap to lock")
        .accessibilityValue(status.text)
    }
}
```

#### Toggle Logic

- **When status is `.auto`:** Button action locks AF/AE
- **When status is `.aeAfLocked` (or other locked states):** Button action unlocks
- **When status is `.unsupported`:** Button is disabled (grayed out)

---

### Phase 2: Wire Toggle in CameraView

**File:** `PromptCam/Views/CameraView.swift`

#### Update cameraHeader() (line ~323)

```swift
return CameraTopControlsView(
    evText: evText,
    lockStatus: viewModel.lockStatus,
    resolutionLabel: viewModel.recordingFormat.resolution.rawValue,
    fpsLabel: viewModel.recordingFormat.frameRate.displayLabel,
    onTapEV: { /* existing EV panel toggle */ },
    onTapGrid: { /* existing grid toggle */ },
    onTapFormat: { /* existing format panel */ },
    onTapLock: {  // NEW
        toggleLockStatus()
    }
)
```

#### Add toggleLockStatus() Method

```swift
/// Toggles AF/AE lock on/off. When locking, uses the center of the frame
/// (or last focus point if available) as the lock target.
private func toggleLockStatus() {
    if viewModel.lockStatus.isLocked {
        // Unlock: return to continuous auto
        viewModel.unlockFocusExposure()
        print("AF/AE unlocked via button -> AUTO")

        // Show brief focus feedback at center
        showCenterFocusFeedback()
    } else {
        // Lock: lock at current center point (or last focus point)
        let lockPoint = focusIndicatorPoint ?? centerPoint()
        let devicePoint = convertToDevicePoint(lockPoint)
        viewModel.lockFocusExposure(at: devicePoint)
        print("AF/AE lock attempted via button")

        // Show brief focus feedback
        showFocusFeedback(at: lockPoint)
    }
}

/// Shows focus indicator at screen center.
private func showCenterFocusFeedback() {
    withAnimation(.easeOut(duration: 0.15)) {
        focusIndicatorPoint = centerPoint()
        showFocusIndicator = true
    }
    scheduleFocusHide()
}

/// Shows focus indicator at specified point.
private func showFocusFeedback(at point: CGPoint) {
    withAnimation(.easeOut(duration: 0.15)) {
        focusIndicatorPoint = point
        showFocusIndicator = true
    }
    scheduleFocusHide()
}

/// Returns the center point of the preview area in view coordinates.
private func centerPoint() -> CGPoint {
    guard let proxy = geometryProxy else { return .zero }
    return CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
}
```

**Note:** We'll need to capture `GeometryProxy` in a `@State` variable to use it in these methods.

---

### Phase 3: Update CameraTopControlsView

**File:** `PromptCam/Views/Camera/CameraTopControlsView.swift`

#### Add onTapLock Closure Parameter

```swift
struct CameraTopControlsView: View {
    let evText: String
    let lockStatus: CameraLockStatus
    let resolutionLabel: String
    let fpsLabel: String

    let onTapEV: () -> Void
    let onTapGrid: () -> Void
    let onTapFormat: () -> Void
    let onTapLock: () -> Void  // NEW

    var body: some View {
        HStack {
            // ... existing format button ...

            Spacer()

            // ... existing EV button ...

            Spacer()

            // Updated: Pass onTapLock to badge
            CameraLockStatusBadgeView(
                status: lockStatus,
                onToggle: onTapLock
            )

            Spacer()

            // ... existing grid button ...
        }
        .padding(.horizontal, Theme.space12)
        .padding(.bottom, Theme.space8)
        .frame(maxWidth: .infinity)
    }
}
```

---

### Phase 4: Simplify FocusIndicatorView

**File:** `PromptCam/Views/FocusIndicatorView.swift`

Replace the complex corner-bracket box + EV slider with a simple thin rectangle.

#### New Simplified Design

```swift
// June 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Simplify to thin yellow rectangle
import SwiftUI

/// Simplified focus indicator: thin yellow rectangle (matches iOS Camera app).
/// Shows briefly after focus tap or lock toggle, then fades out after 3 seconds.
struct FocusIndicatorView: View {
    let showFocusIndicator: Bool

    var body: some View {
        if showFocusIndicator {
            Rectangle()
                .strokeBorder(Theme.yellow, lineWidth: 2)
                .frame(width: 80, height: 80)
                .transition(.opacity)
        }
    }
}
```

**Changes:**

- **Removed:** Corner brackets, EV slider rail, sun icon, EV label, drag gesture
- **Added:** Simple stroked rectangle (80×80pt, 2pt line width)
- **Behavior:** Same fade-out timing (3 seconds via `scheduleFocusHide()`)

---

### Phase 5: Remove Long-Press Lock Gesture

**File:** `PromptCam/Views/CameraView.swift`

Since the teleprompter interferes with long-press, and we now have a dedicated button, remove the long-press gesture handler.

#### Remove Long-Press from CameraPreviewView

In `CameraPreviewView.swift` (or wherever the preview tap/long-press gestures are wired):

```swift
CameraPreviewView(
    session: viewModel.session,
    onTap: { devicePoint, viewPoint in
        handlePreviewTap(devicePoint: devicePoint, viewPoint: viewPoint, barHeight: barHeight)
    }
    // REMOVE: onLongPress callback
)
```

#### Remove handlePreviewLongPress() Method

Delete the `handlePreviewLongPress()` method from `CameraView.swift` (line ~384).

#### Update handlePreviewTap() Logic

Simplify tap handler — no longer needs to check for locked state and unlock:

```swift
/// Handles single tap to focus at the touched point.
private func handlePreviewTap(devicePoint: CGPoint, viewPoint: CGPoint, barHeight: CGFloat) {
    viewModel.focus(at: devicePoint)
    print("Touch Focus at point")
    updateFocusIndicatorPosition(viewPoint: viewPoint, barHeight: barHeight)
    scheduleFocusHide()
}
```

**Removed logic:**

```swift
// OLD: Unlock if currently locked
if viewModel.lockStatus != .auto {
    viewModel.unlockFocusExposure()
    print("AE/AF lock released")
}
```

Now tapping the preview only focuses — it does NOT unlock. Users must tap the lock button to unlock.

---

### Phase 6: Remove EV Drag Gesture from Focus Indicator

**File:** `PromptCam/Views/CameraView.swift`

Since FocusIndicatorView no longer accepts drag input (we moved EV to dedicated panel), remove related state and handlers.

#### Remove State Variables

```swift
// REMOVE these:
@State private var lastExposureDrag: CGSize = .zero
@State private var exposureDebounceWorkItem: DispatchWorkItem?
@State private var exposureDragBaselineBias: Float = 0
@State private var exposureDragBaselineY: CGFloat = 0
```

Keep these (used by EV panel):

```swift
@State private var exposureBias: Float = 0
@State private var lastAppliedExposureBias: Float = 0
```

#### Update FocusIndicatorView Call

Remove drag callback:

```swift
if showFocusIndicator, let focusIndicatorPoint {
    FocusIndicatorView(
        showFocusIndicator: showFocusIndicator
    )
    .position(focusIndicatorPoint)
}
```

#### Remove handleExposureDrag() Method

Delete the `handleExposureDrag()` method entirely (line ~393).

---

### Phase 7: Show Focus Indicator on Camera Start

**File:** `PromptCam/Views/CameraView.swift`

When the camera view appears, show the focus indicator briefly at center to signal that AF/AE are active.

#### Add onAppear Handler

```swift
.onAppear {
    viewModel.onAppear()

    // Show brief center focus feedback on camera start
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        showCenterFocusFeedback()
    }
}
```

---

## Visual Reference

### Before (Current)

```
┌─────────────────────────────────────┐
│ [Format] [EV +1.2] [AUTO] [Grid]   │  ← Lock status is passive text
│                                     │
│    ┏━━━━━━┓                        │  ← Complex focus box
│    ┃ ☀️EV  ┃                        │     with corner brackets
│    ┃ +1.2  ┃ ━━ EV slider          │     + vertical EV slider
│    ┗━━━━━━┛                        │
│                                     │
│     [Camera Preview]                │
│                                     │
│     Long-press to lock (broken!)   │
└─────────────────────────────────────┘
```

### After (Proposed)

```
┌─────────────────────────────────────┐
│ [Format] [EV +1.2] [AUTO ▾] [Grid] │  ← Lock button (tappable)
│                                     │
│        ┌──────┐                    │  ← Simple thin rectangle
│        │      │                    │     (shows on focus/lock)
│        └──────┘                    │     (fades after 3s)
│                                     │
│     [Camera Preview]                │
│                                     │
│     Tap to focus                   │
│     Tap [AUTO] to lock/unlock      │
│     Tap [EV] for exposure panel    │
└─────────────────────────────────────┘
```

---

## Testing Checklist

### Before Approval

- [ ] Review plan structure and component breakdown
- [ ] Confirm lock toggle behavior (tap to lock/unlock at center or last focus point)
- [ ] Verify simplified focus indicator design (thin rectangle, no EV slider)
- [ ] Confirm removal of long-press gesture (teleprompter conflict resolved)

### After Implementation

#### Lock Toggle Button

- [ ] Button shows "AUTO" (green) when unlocked
- [ ] Button shows "AE/AF LOCK" (yellow) when locked
- [ ] Tapping button locks AF/AE at center (or last focus point)
- [ ] Tapping button again unlocks and returns to AUTO
- [ ] Button is disabled (grayed) if device doesn't support lock
- [ ] Lock status updates correctly after toggle
- [ ] Print statements confirm lock/unlock actions

#### Simplified Focus Indicator

- [ ] Thin yellow rectangle (80×80pt, 2pt stroke) appears on focus tap
- [ ] Indicator appears when toggling lock button
- [ ] Indicator appears briefly at center when camera opens
- [ ] Indicator fades out after 3 seconds
- [ ] No corner brackets, no EV slider, no sun icon
- [ ] Indicator does not interfere with teleprompter layer

#### Gesture Cleanup

- [ ] Tap preview focuses at point (shows indicator)
- [ ] Long-press gesture removed (no longer triggers lock)
- [ ] EV drag gesture removed (use dedicated EV panel instead)
- [ ] Teleprompter swipe gestures work without conflict

#### Integration

- [ ] EV bias control via dedicated EV adjustment panel works
- [ ] Lock toggle + EV panel + teleprompter panel all coexist without conflict
- [ ] Opening any panel doesn't interfere with lock state
- [ ] Lock state persists while adjusting EV bias

---

## File Checklist

### Modified Files

- [ ] `PromptCam/Views/Camera/CameraLockStatusBadgeView.swift`
  - Add `onToggle: () -> Void` parameter
  - Wrap text in Button
  - Add disabled state for unsupported devices

- [ ] `PromptCam/Views/Camera/CameraTopControlsView.swift`
  - Add `onTapLock: () -> Void` parameter
  - Pass `onToggle: onTapLock` to badge view

- [ ] `PromptCam/Views/FocusIndicatorView.swift`
  - Replace with simplified thin rectangle design
  - Remove corner brackets, EV slider, drag gesture
  - Keep fade-in/fade-out transition

- [ ] `PromptCam/Views/CameraView.swift`
  - Add `toggleLockStatus()` method
  - Add `showCenterFocusFeedback()` helper
  - Add `showFocusFeedback(at:)` helper
  - Add `centerPoint()` helper
  - Update `cameraHeader()` to pass `onTapLock` callback
  - Remove `handlePreviewLongPress()` method
  - Simplify `handlePreviewTap()` (remove unlock logic)
  - Remove `handleExposureDrag()` method
  - Remove EV drag-related state variables
  - Update FocusIndicatorView instantiation (remove drag props)
  - Add onAppear handler to show center focus on start
  - Capture GeometryProxy in @State if needed for centerPoint()

- [ ] `PromptCam/Views/CameraPreviewView.swift` (or wrapper)
  - Remove `onLongPress` callback parameter
  - Keep `onTap` callback only

### No New Files

All changes are modifications to existing files.

---

## Notes

1. **Lock Target Point:**
   - When locking via button, use last focus point if available, otherwise screen center
   - iOS Camera app locks at the last focused point
   - Provides predictable behavior: "tap to focus, tap lock button to hold that focus"

2. **Unsupported Devices:**
   - Front-facing cameras often don't support true AF lock (fixed focus)
   - Keep `.unsupported` state logic from `CameraViewModel`
   - Disable lock button when status is `.unsupported`
   - Show "LOCK UNAVAILABLE" text (yellow)

3. **EV Control Separation:**
   - Exposure bias adjustment now lives entirely in the dedicated EV panel
   - Focus indicator no longer needs EV slider or drag gesture
   - Cleaner separation of concerns: focus/lock vs. exposure bias

4. **Gesture Conflicts Resolved:**
   - **Before:** Tap focus + long-press lock + drag EV (all on preview)
   - **After:** Tap focus (on preview) + button lock + EV panel (separate)
   - Teleprompter swipe gestures no longer conflict with lock gesture

5. **Fade Timing:**
   - Keep existing 3-second fade via `scheduleFocusHide()`
   - Indicator stays visible while locked (never fades if `lockStatus.isLocked`)
   - Matches current behavior

6. **Visual Alignment:**
   - Thin rectangle matches iOS Camera app aesthetic
   - Yellow color retained (consistent with existing AF/AE lock color)
   - 80×80pt size is similar to iOS focus square

---

## Ready for Review

This plan is complete and ready for your approval. Once approved, we can proceed with:

1. Converting badge to button
2. Simplifying focus indicator
3. Adding toggle logic
4. Removing long-press gesture
5. Testing all interactions on device

**Questions before coding:**

1. **Lock target:** Should the button always lock at screen center, or use last focus point if available?
2. **Indicator size:** Is 80×80pt appropriate for the thin rectangle, or would you prefer larger/smaller?
3. **Button visual:** Should the button have additional visual affordance (e.g., subtle background) or keep it text-only?
4. **Lock persistence:** Should lock state persist when switching between camera/compose modes, or auto-unlock?
