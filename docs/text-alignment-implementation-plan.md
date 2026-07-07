# Text Alignment Toggle Button — Implementation Plan

**Created:** July 6, 2026  
**Goal:** Add a 3-state cycling button to control teleprompter text alignment (center → left → right → center)

---

## Overview

Add a new toggle button positioned to the LEFT of the record button (mirroring the scroll button's position on the right) that cycles through three text alignment states continuously.

---

## Design Specifications

### Button Appearance

- **Icon:** SF Symbols
  - Center: `text.aligncenter` (default state)
  - Left: `text.alignleft`
  - Right: `text.alignright`
- **Color:** `Theme.white`
- **Size:** `icon32` (32pt SF Symbol)
- **Container:** 40×40 pt circle (matches ScrollToggleButton size)
- **Style:** White stroke border (4pt), filled circle background similar to scroll button

### Button Positioning

- **Location:** LEFT of the record button
- **Offset:** `-72` (negative x-offset, same distance as scroll button but opposite side)
- **Parent:** `RecordingClusterView` (alongside RecordButton and ScrollToggleButton)

### Button Behavior

- **Cycling order:** center → left → right → center (continuous loop)
- **Icon updates:** Changes to reflect current alignment state
- **Persistence:** Last-used alignment saved to UserDefaults via TeleprompterConfig

---

## Implementation Steps

### Step 1: Add Text Alignment to TeleprompterConfig Model

**File:** `PromptCam/Models/TeleprompterConfig.swift`

**Changes:**

1. Add `TextAlignment` enum at top of file:

   ```swift
   enum TeleprompterTextAlignment: String, CaseIterable, Equatable, Sendable {
       case center
       case left
       case right

       var swiftUIAlignment: TextAlignment {
           switch self {
           case .center: return .center
           case .left: return .leading
           case .right: return .trailing
           }
       }

       var iconName: String {
           switch self {
           case .center: return "text.aligncenter"
           case .left: return "text.alignleft"
           case .right: return "text.alignright"
           }
       }

       /// Returns the next alignment in the cycle: center → left → right → center
       var next: TeleprompterTextAlignment {
           switch self {
           case .center: return .left
           case .left: return .right
           case .right: return .center
           }
       }
   }
   ```

2. Add `textAlignment` property to `TeleprompterConfig` struct:

   ```swift
   var textAlignment: TeleprompterTextAlignment
   ```

3. Update `default` config to include alignment:
   ```swift
   static let `default` = TeleprompterConfig(
       text: "Tap script button below to load your script.",
       speedPointsPerSecond: 35,
       fontSize: 30,
       textColor: .white,
       backgroundOpacity: 0.15,
       textAlignment: .center  // ← Add this
   )
   ```

---

### Step 2: Create AlignmentToggleButton Component

**File:** `PromptCam/Views/Camera/RecordingClusterView.swift`

**Changes:**
Add new button component after `ScrollToggleButton`:

```swift
// MARK: - Alignment Toggle Button

/// Tertiary control to cycle through text alignment options.
/// White circle with alignment icon (center/left/right).
struct AlignmentToggleButton: View {
    /// Current text alignment state.
    let alignment: TeleprompterTextAlignment
    /// Callback to advance to next alignment.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Theme.white, lineWidth: 4)
                Circle().fill(Theme.blue)
                Image(systemName: alignment.iconName)
                    .font(Theme.icon32)
                    .foregroundStyle(Theme.white)
            }
        }
        .accessibilityLabel("Text alignment: \(alignment.rawValue)")
        .accessibilityHint("Cycles between center, left, and right alignment")
    }
}
```

---

### Step 3: Update RecordingClusterView Layout

**File:** `PromptCam/Views/Camera/RecordingClusterView.swift`

**Changes:**

1. Add alignment parameter and callback to `RecordingClusterView`:

   ```swift
   struct RecordingClusterView: View {
       let isRecording: Bool
       let isScrolling: Bool
       let isRecordEnabled: Bool
       let textAlignment: TeleprompterTextAlignment  // ← Add this
       let onRecordTap: () -> Void
       let onScrollTap: () -> Void
       let onAlignmentTap: () -> Void  // ← Add this
   ```

2. Update body to include alignment button:

   ```swift
   var body: some View {
       ZStack {
           RecordButton(isRecording: isRecording, isEnabled: isRecordEnabled, action: onRecordTap)
               .frame(width: 72, height: 72)

           ScrollToggleButton(isScrolling: isScrolling, action: onScrollTap)
               .frame(width: 40, height: 40)
               .offset(x: 72)

           AlignmentToggleButton(alignment: textAlignment, action: onAlignmentTap)
               .frame(width: 40, height: 40)
               .offset(x: -72)  // ← LEFT of record button
       }
   }
   ```

---

### Step 4: Wire to CameraViewModel

**File:** `PromptCam/ViewModels/CameraViewModel.swift`

**Changes:**

1. Add method to cycle alignment:

   ```swift
   @MainActor
   func cycleTextAlignment() {
       config.textAlignment = config.textAlignment.next
       saveTeleprompterConfig()
       print("Text alignment cycled to: \(config.textAlignment.rawValue)")
   }
   ```

2. Verify `saveTeleprompterConfig()` includes the new `textAlignment` field when saving to UserDefaults.

---

### Step 5: Update CameraView to Pass Alignment

**File:** `PromptCam/Views/CameraView.swift`

**Changes:**

Update the `RecordingClusterView` call site (around line 118) to include alignment:

```swift
RecordingClusterView(
    isRecording: viewModel.isRecording,
    isScrolling: viewModel.isScrolling,
    isRecordEnabled: viewModel.isCameraReady,
    textAlignment: viewModel.config.textAlignment,  // ← Add this
    onRecordTap: {
        viewModel.toggleRecording()
    },
    onScrollTap: {
        viewModel.toggleScrolling()
    },
    onAlignmentTap: {
        viewModel.cycleTextAlignment()
    }
)
```

---

### Step 6: Apply Alignment to ScrollingTeleprompterText

**File:** `PromptCam/Views/Teleprompter/ScrollingTeleprompterText.swift`

**Changes:**

1. Add `alignment` parameter:

   ```swift
   struct ScrollingTeleprompterText: View {
       let text: String
       let fontSize: Double
       let textColor: Color
       let alignment: TextAlignment  // ← Add this
       let offsetY: CGFloat
   ```

2. Update `.multilineTextAlignment()` to use the parameter:
   ```swift
   Text(text)
       .font(Theme.fontFamily.rounded(size: fontSize, weight: .semibold))
       .foregroundStyle(textColor)
       .multilineTextAlignment(alignment)  // ← Changed from .center
   ```

---

### Step 7: Update TeleprompterOverlayView to Pass Alignment

**File:** `PromptCam/Views/TeleprompterOverlayView.swift`

**Changes:**

Update both `ScrollingTeleprompterText` call sites (animated and static branches) to include alignment:

```swift
// Animated branch (around line 47)
ScrollingTeleprompterText(
    text: config.text,
    fontSize: config.fontSize,
    textColor: config.textColor.color,
    alignment: config.textAlignment.swiftUIAlignment,  // ← Add this
    offsetY: totalY
)

// Static branch (around line 54)
ScrollingTeleprompterText(
    text: config.text,
    fontSize: config.fontSize,
    textColor: config.textColor.color,
    alignment: config.textAlignment.swiftUIAlignment,  // ← Add this
    offsetY: staticOffsetY
)
```

---

### Step 8: Add Preview for AlignmentToggleButton

**File:** `PromptCam/Views/Camera/RecordingClusterView.swift`

**Changes:**

Add preview at bottom of file:

```swift
#Preview("AlignmentToggleButton - Center") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        AlignmentToggleButton(alignment: .center) {}
            .frame(width: 40, height: 40)
    }
}

#Preview("AlignmentToggleButton - Left") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        AlignmentToggleButton(alignment: .left) {}
            .frame(width: 40, height: 40)
    }
}

#Preview("AlignmentToggleButton - Right") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        AlignmentToggleButton(alignment: .right) {}
            .frame(width: 40, height: 40)
    }
}
```

---

### Step 9: Update TeleprompterConfigTests

**File:** `PromptCamTests/TeleprompterConfigTests.swift`

**Changes:**

Add test for alignment cycling:

```swift
func testTextAlignmentCycle() {
    XCTAssertEqual(TeleprompterTextAlignment.center.next, .left)
    XCTAssertEqual(TeleprompterTextAlignment.left.next, .right)
    XCTAssertEqual(TeleprompterTextAlignment.right.next, .center)
}

func testTextAlignmentSwiftUIMapping() {
    XCTAssertEqual(TeleprompterTextAlignment.center.swiftUIAlignment, .center)
    XCTAssertEqual(TeleprompterTextAlignment.left.swiftUIAlignment, .leading)
    XCTAssertEqual(TeleprompterTextAlignment.right.swiftUIAlignment, .trailing)
}

func testTextAlignmentIcons() {
    XCTAssertEqual(TeleprompterTextAlignment.center.iconName, "text.aligncenter")
    XCTAssertEqual(TeleprompterTextAlignment.left.iconName, "text.alignleft")
    XCTAssertEqual(TeleprompterTextAlignment.right.iconName, "text.alignright")
}
```

---

## Testing Checklist

### Visual Layout

- [ ] Alignment button appears LEFT of record button
- [ ] Button size matches scroll button (40×40 pt)
- [ ] Icon renders at 32pt size with Theme.white color
- [ ] Button has white stroke border (4pt) and blue fill
- [ ] Three buttons (alignment, record, scroll) are visually balanced

### Functionality

- [ ] Tapping button cycles: center → left → right → center
- [ ] Icon changes immediately to reflect current state
- [ ] Text alignment in teleprompter updates immediately
- [ ] Alignment persists across app launches (saved to UserDefaults)
- [ ] Button works while scrolling is active
- [ ] Button is disabled during recording (matches other footer button behavior)

### Edge Cases

- [ ] Default alignment is center on first launch
- [ ] Alignment survives script changes
- [ ] Alignment works with all font sizes (16–72pt)
- [ ] Alignment works with all text colors
- [ ] Preview builds all render correctly

---

## Files Modified

| File                              | Changes                                                         |
| --------------------------------- | --------------------------------------------------------------- |
| `TeleprompterConfig.swift`        | Add `TeleprompterTextAlignment` enum + `textAlignment` property |
| `RecordingClusterView.swift`      | Add `AlignmentToggleButton` component + wire to layout          |
| `CameraViewModel.swift`           | Add `cycleTextAlignment()` method                               |
| `CameraView.swift`                | Pass alignment state to RecordingClusterView                    |
| `ScrollingTeleprompterText.swift` | Add `alignment` parameter, use in `.multilineTextAlignment()`   |
| `TeleprompterOverlayView.swift`   | Pass alignment to ScrollingTeleprompterText (2 call sites)      |
| `TeleprompterConfigTests.swift`   | Add unit tests for alignment cycling                            |

**Total Files Modified:** 7

---

## Visual Layout Reference

```
                    [ Camera Preview ]

                     [Recording Timer]

          [Align]    [Record]    [Scroll]
            ↑          ↑            ↑
         -72 offset   center    +72 offset
         (new)                   (existing)
```

---

## Notes

- **Consistency:** Button styling matches existing `ScrollToggleButton` (white border, blue fill)
- **Accessibility:** Includes proper labels and hints for VoiceOver
- **Persistence:** Alignment saved via existing `saveTeleprompterConfig()` UserDefaults mechanism
- **Print debugging:** Added `print()` statement in `cycleTextAlignment()` for Xcode console testing
- **Icon size:** Uses `icon32` (not `icon12` like scroll button) per specifications
- **No recording state needed:** Unlike scroll button, alignment doesn't need play/pause states — just cycles through options

---

## Questions Before Implementation

1. **Button styling:** Should the alignment button use the same blue fill as the scroll button, or a different color to differentiate it?
2. **Recording behavior:** Should the alignment button be disabled during recording (like other footer controls), or remain active?
3. **Default alignment:** Confirm center alignment is the desired default for first-time users?
4. **Adjustment panel:** Should the alignment control also appear in the TeleprompterAdjustmentPanel for consistency?

---

**Ready for approval.** Once confirmed, I'll implement all changes in a single pass.
