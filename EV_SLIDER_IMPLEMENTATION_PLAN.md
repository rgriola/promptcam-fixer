# EV Slider Implementation Plan

**Created:** June 7, 2026  
**Agent:** GitHub Copilot (Claude Sonnet 4.6)

## Overview

Add an exposure value (EV) control slider panel that slides down from the EV button in `CameraTopControlsView`. This will provide live adjustment of camera exposure using the existing `adjustExposure()` function, following the same UX pattern as the teleprompter adjustment panel.

---

## Current State Analysis

### Existing Components

1. **EV Button** — `CameraTopControlsView.swift` (line ~65)
   - Currently prints "EV button tapped" on tap
   - Displays current EV value as "EV ±X.X"
   - Uses `Theme.mono16Medium` monospaced font

2. **Exposure State** — `CameraView.swift`
   - `exposureBias: Float` — current EV value shown in UI
   - `exposureRange: Float = 5.0` — max absolute EV (±5.0)
   - `lastAppliedExposureBias: Float` — last value sent to camera

3. **Exposure Control** — `CameraViewModel.swift`
   - `adjustExposure(by delta: Float)` — sends incremental delta to camera service
   - Connected to AF/AE focus indicator drag gesture

4. **Reference Pattern** — `TeleprompterAdjustmentPanel.swift`
   - Slides up from bottom with `.move(edge: .bottom)` transition
   - Uses `.ultraThinMaterial` background
   - Live adjustments via `@Binding`
   - Tap-outside-to-dismiss overlay
   - Reset button returns to defaults

---

## Implementation Plan

### Phase 1: Create EVAdjustmentPanel Component

**File:** `PromptCam/Views/Camera/EVAdjustmentPanel.swift`

#### Component Structure

```swift
/// Slide-down panel for live exposure value adjustment.
/// Positioned below the EV button in the camera header.
/// Spans horizontally to match button width or slightly wider.
/// Changes are live (no confirm needed).
struct EVAdjustmentPanel: View {
    @Binding var exposureBias: Float
    let exposureRange: Float
    let onReset: () -> Void
    let onAdjust: (Float) -> Void  // Called on slider value change

    var body: some View {
        // Panel implementation
    }
}
```

#### Panel Layout

1. **Container**
   - `.ultraThinMaterial` background (matches teleprompter panel)
   - Rounded corners: `Theme.radiusMd`
   - Horizontal padding: `Theme.space12`
   - Vertical padding: `Theme.space12`

2. **EV Slider Row**
   - Label: "EV"
   - Slider: `-exposureRange...exposureRange` (±5.0)
   - Step: 0.1 (fine control)
   - Value display: "±X.X" with monospaced digits
   - Tint: `Theme.blue`
   - Control size: `.large`

3. **Hash Marks**
   - Visual marks at -5, 0, +5 positions below slider
   - Implemented as small vertical rectangles aligned with scale labels
   - Height: 6pt, Width: 1pt, Color: `Theme.secondaryText`

4. **Auto Button**
   - Text: "Auto" (replaces "Reset to 0")
   - Action: Sets `exposureBias = 0` and calls `onReset()`
   - Meaning: Return to neutral automatic exposure (no bias)
   - Style: Glass overlay with blue text (matches teleprompter)
   - Full-width button below slider

#### Slider Interaction

- **Live updates:** Slider changes immediately update `@Binding var exposureBias`
- **Camera updates:** `onAdjust(Float)` callback sends delta to camera via `adjustExposure(by:)`
- **Delta calculation:** Compare new value to previous value to compute incremental delta

---

### Phase 2: Add Panel State to CameraView

**File:** `PromptCam/Views/CameraView.swift`

#### State Variables

Add after line 54 (with other panel state):

```swift
/// Controls visibility of the EV adjustment panel.
@State private var showEVPanel: Bool = false
```

#### Panel Toggle Action

Update `cameraHeader()` function (line ~277):

```swift
onTapEV: {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
        showEVPanel.toggle()
        // Close teleprompter panel if open (mutual exclusion)
        if showEVPanel {
            showAdjustmentPanel = false
        }
    }
    print("EV panel toggled -> \(showEVPanel)")
}
```

---

### Phase 3: Position Panel in View Hierarchy

**File:** `PromptCam/Views/CameraView.swift`

Add as **Layer 8** after the teleprompter panel (after line ~194):

```swift
// Layer 8: EV adjustment panel — slides down from EV button.
if showEVPanel {
    VStack(spacing: 0) {
        // Panel container aligned to top-leading (below EV button)
        HStack {
            EVAdjustmentPanel(
                exposureBias: $exposureBias,
                exposureRange: exposureRange,
                onReset: {
                    exposureBias = 0
                    let delta = -lastAppliedExposureBias
                    viewModel.adjustExposure(by: delta)
                    lastAppliedExposureBias = 0
                    print("EV reset to 0")
                },
                onAdjust: { newBias in
                    let delta = newBias - lastAppliedExposureBias
                    viewModel.adjustExposure(by: delta)
                    lastAppliedExposureBias = newBias
                }
            )
            .frame(width: 240) // Fixed width for slider
            .padding(.top, safeTopInset + Theme.space8) // Below header
            .padding(.leading, Theme.space12)

            Spacer()
        }

        Spacer()

        // Tap-off-screen dismiss area
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showEVPanel = false
                }
                print("EV panel dismissed via tap-outside")
            }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .transition(.move(edge: .top).combined(with: .opacity))
}
```

#### Positioning Details

- **Anchor point:** Top-leading corner (below EV button)
- **Width:** ~240pt (comfortable slider width, not full screen)
- **Top offset:** `safeTopInset + Theme.space8` (clears the header controls)
- **Transition:** `.move(edge: .top)` — slides down from top (opposite of teleprompter's bottom slide)
- **Dismissal:** Tap anywhere outside panel to close

---

### Phase 4: Panel Component Implementation Details

**File:** `PromptCam/Views/Camera/EVAdjustmentPanel.swift`

#### Slider Row Component

```swift
private struct EVSliderRow: View {
    @Binding var exposureBias: Float
    let exposureRange: Float
    let onAdjust: (Float) -> Void

    var valueLabel: String {
        let sign = exposureBias >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", exposureBias))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            HStack {
                Text("EV")
                    .font(Theme.font16Medium)
                    .foregroundStyle(Theme.blackText)

                Spacer()

                Text(valueLabel)
                    .font(Theme.mono16Medium)
                    .foregroundStyle(Theme.blackText)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(exposureBias) },
                    set: { newValue in
                        let newBias = Float(newValue)
                        exposureBias = newBias
                        onAdjust(newBias)
                    }
                ),
                in: Double(-exposureRange)...Double(exposureRange),
                step: 0.1
            )
            .controlSize(.large)
            .tint(Theme.blue)

            // Hash marks at -5, 0, +5
            HStack {
                Rectangle()
                    .fill(Theme.secondaryText)
                    .frame(width: 1, height: 6)

                Spacer()

                Rectangle()
                    .fill(Theme.blackText)
                    .frame(width: 1, height: 6)

                Spacer()

                Rectangle()
                    .fill(Theme.secondaryText)
                    .frame(width: 1, height: 6)
            }
            .padding(.top, 2)

            // Min/Center/Max labels
            HStack {
                Text("\(String(format: "%.0f", -exposureRange))")
                    .font(Theme.font10Regular)
                    .foregroundStyle(Theme.secondaryText)

                Spacer()

                Text("0")
                    .font(Theme.font10Medium)
                    .foregroundStyle(Theme.blackText)

                Spacer()

                Text("+\(String(format: "%.0f", exposureRange))")
                    .font(Theme.font10Regular)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
```

#### Auto Button

```swift
private struct AutoButton: View {
    let onReset: () -> Void

    var body: some View {
        Button(action: onReset) {
            Text("Auto")
                .font(Theme.font16Medium)
                .foregroundStyle(Theme.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.space8)
                .background(Theme.glassOverlay, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
        }
        .accessibilityLabel("Auto exposure")
        .accessibilityHint("Returns to neutral automatic exposure")
    }
}
```

---

## Testing Checklist

### Before Approval

- [ ] Review plan structure and component breakdown
- [ ] Confirm panel positioning (slides down from EV button, top-leading anchor)
- [ ] Verify interaction pattern matches teleprompter panel (tap-outside dismiss, live updates)
- [ ] Check Theme constants availability (`glassOverlay`, `blackText`, `secondaryText`)

### After Implementation

- [ ] EV button toggles panel visibility with spring animation
- [ ] Panel slides down from top below EV button
- [ ] Slider range is ±5.0 with 0.1 step
- [ ] Value label shows ±X.X format with monospaced digits
- [ ] Live slider updates camera exposure smoothly
- [ ] Hash marks appear at -5, 0, +5 positions
- [ ] Auto button returns exposure to 0 and updates camera
- [ ] Tap outside panel dismisses it with animation
- [ ] Opening EV panel closes teleprompter panel (mutual exclusion)
- [ ] Panel does not interfere with AF/AE tap focus gesture
- [ ] Panel respects safe area insets on notched devices
- [ ] Print statements confirm button taps and value changes

---

## Visual Reference

```
┌─────────────────────────────────────┐
│  [Format]  [EV +2.3]  [Lock] [•]    │  ← Tap EV to open
│                                     │
│  ┌──────────────────┐              │  ← Panel slides down
│  │ EV          +2.3 │              │
│  │ ━━━━━●━━━━━━━━━ │              │
│  │ |     |       |  │  ← Hash marks
│  │ -5    0      +5  │              │
│  │                  │              │
│  │     [ Auto ]     │  ← Reset to neutral auto
│  └──────────────────┘              │
│                                     │
│    [Camera Preview]                │
│                                     │
│    [Record] [Scroll]               │
└─────────────────────────────────────┘
```

---

## File Checklist

### New Files

- [ ] `PromptCam/Views/Camera/EVAdjustmentPanel.swift`

### Modified Files

- [ ] `PromptCam/Views/CameraView.swift`
  - Add `@State private var showEVPanel`
  - Update `onTapEV` closure in `cameraHeader()`
  - Add Layer 8 for EV panel with positioning

---

## Notes

1. **Panel Width:** Using fixed 240pt width instead of full screen to keep panel compact and visually aligned with the EV button. This differs from the teleprompter panel which spans full width.

2. **Transition Direction:** Panel slides from `.top` (down) instead of `.bottom` (up) to match the button's position in the header.

3. **Mutual Exclusion:** Opening the EV panel should close the teleprompter panel if open, preventing visual clutter and ensuring only one adjustment surface is active. Yes

4. **Delta-based Updates:** Camera exposure uses incremental deltas via `adjustExposure(by:)`, not absolute values. The panel must track `lastAppliedExposureBias` to compute correct deltas.

5. **Live Feedback:** Slider changes are immediate — no "Apply" button needed. This matches native camera app behavior where EV adjustments are instant.

6. **Theme Dependencies:** Verify these Theme constants exist:
   - `Theme.glassOverlay` (used in reset button background)
   - `Theme.blackText` (used for labels)
   - `Theme.secondaryText` (used for min/max range labels)
   - If missing, use `Color.black.opacity(0.1)` for glassOverlay

---

## Ready for Review

This plan is complete and ready for your approval. Once approved, we can proceed with:

1. Creating `EVAdjustmentPanel.swift` component
2. Updating `CameraView.swift` state and layout
3. Testing all interactions on device

**Approved Design (Option 3):**

✅ **Panel width:** 240pt (adjustable later if needed)
✅ **Mutual exclusion:** EV panel auto-closes teleprompter panel
✅ **Hash marks:** At -5, 0, +5 positions
✅ **Slider sensitivity:** 0.1 step (100 positions across ±5.0)
✅ **Auto button:** Replaces "Reset to 0" — returns to neutral automatic exposure

**Design Rationale:**

- EV button always shows current value, taps to open/close panel
- "Auto" button is clear and prominent — means "return to neutral auto exposure"
- Hash marks provide visual reference for key positions
- Matches iOS camera app UX pattern
