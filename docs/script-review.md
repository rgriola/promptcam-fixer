# ComposeScriptSheet.swift — Code Review

**Date:** 2026-07-01  
**File:** `PromptCam/Views/Sheets/ComposeScriptSheet.swift`  
**Context:** User reported "glitches" without specifics

## Overall Assessment

Functional but has several best-practice violations and potential glitch sources. The reported glitches likely stem from timing/animation issues around keyboard presentation and view dismissal.

---

## 🔴 Critical Issues

### 1. Untracked Task Creates Memory Leak Risk

**Location:** Lines 172-175 (Clean button action)

```swift
Task {
    try? await Task.sleep(for: .seconds(1.5))
    didClean = false
}
```

**Problem:**

- Creates orphaned Task that survives view dismissal
- If user saves/cancels within 1.5s, Task still runs and tries to mutate deallocated state
- No cancellation mechanism when view disappears

**Fix:**
Store as `@State private var cleanIndicatorTask: Task<Void, Never>?` and cancel in `dismissAndRun` or `.onDisappear`

**Best practice example:**
`RecordingPlayerView` does this correctly with `hideControlsTask`:

```swift
@State private var hideControlsTask: Task<Void, Never>?

private func scheduleControlsHide() {
    hideControlsTask?.cancel()
    hideControlsTask = Task {
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        withAnimation { showControls = false }
    }
}
```

---

### 2. Commented-Out Code Signals Unresolved Timing Issue

**Location:** Lines 212-217

```swift
.task {
    // Delay keyboard focus until the cover presentation animation
    // completes (~0.5s). The text editor is pre-sized so the keyboard
    // fills the space below without resizing anything.
   // try? await Task.sleep(for: .milliseconds(500))
    isEditorFocused = true
}
```

**Problem:**

- Comment says delay is needed for animation completion but code was removed
- Likely source of glitches: keyboard may appear before sheet animation finishes, causing layout jumps
- Comment contradicts implementation

**Fix:**
Either:

1. Restore the delay if it was fixing a real issue
2. Remove the comment if delay is unnecessary
3. Document why the delay was removed

---

### 3. Old-Style Async Pattern

**Location:** Lines 120-125 (`dismissAndRun` helper)

```swift
private func dismissAndRun(_ action: @escaping () -> Void) {
    isEditorFocused = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        action()
    }
}
```

**Problems:**

- Uses GCD instead of Swift Concurrency
- Magic number `0.35` hardcoded (should match system animation duration)
- Not cancellable if view dismisses during the 0.35s window
- May cause race conditions if timing is wrong

**Better pattern:**

```swift
@State private var dismissTask: Task<Void, Never>?

private func dismissAndRun(_ action: @escaping () -> Void) {
    dismissTask?.cancel()
    isEditorFocused = false
    dismissTask = Task {
        try? await Task.sleep(for: .seconds(0.35))
        guard !Task.isCancelled else { return }
        action()
    }
}
```

---

## ⚠️ Design Issues

### 4. GeometryReader-Based Layout Can Cause Instability

**Location:** Lines 130-131

```swift
GeometryReader { geo in
    let editorHeight = geo.size.height * 0.45
```

**Problem:**

- Fixed 45% height recalculates on every GeometryReader update
- With keyboard transitions, `geo.size` changes → editor height changes → potential layout thrash
- The `.ignoresSafeArea(.keyboard)` on the VStack might not prevent this
- GeometryReader can trigger multiple re-layouts during animations

**Potential fix:**
Consider fixed height instead of percentage, or cache the initial height:

```swift
@State private var editorHeight: CGFloat?

GeometryReader { geo in
    Color.clear.onAppear {
        if editorHeight == nil {
            editorHeight = geo.size.height * 0.45
        }
    }
}
```

---

### 5. onChange Modifies Its Own Observed Value

**Location:** Lines 159-163

```swift
.onChange(of: draftText) { _, newValue in
    if newValue.count > Self.kMaxScriptLength {
        draftText = String(newValue.prefix(Self.kMaxScriptLength))
    }
}
```

**Problem:**

- Generally discouraged pattern (can cause race conditions in complex views)
- Works here but fragile
- Modifying the observed value inside its own observer can lead to recursive updates

**Better approaches:**

1. Use a custom Binding with validation
2. Use Combine `$draftText.removeDuplicates()` publisher
3. Validate in a setter wrapper

---

### 6. Inconsistent Truncation Logic

**Location:** Multiple places

**Problems:**

- Save button disabled when `draftText.trimmingCharacters(...).isEmpty` (line 240)
- But save action does `String(sanitized.prefix(Self.kMaxScriptLength))` (line 236)
- User can have 15,000 chars → Save enabled → silently truncated to 10,000 on save
- Character count shows red when over limit (line 137) but doesn't prevent typing beyond it
- `onChange` truncates at typing time (line 161), but save also truncates (line 236)

**Impact:**
User may not realize their script was truncated. Should show alert or disable save when over limit.

---

## 📝 Code Quality Issues

### 7. Duplicated String Trimming

**Locations:**

- Save button `isDisabled` check (line 240)
- `cleanForTeleprompter()` final step (line 115)
- `sanitizeScript()` first step (line 41)

**Fix:**
Not critical but could extract to helper or computed property:

```swift
private var trimmedDraftText: String {
    draftText.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

---

### 8. Magic Numbers

**Locations throughout file:**

- `0.35` seconds for keyboard dismissal (line 122)
- `1.5` seconds for clean indicator (line 172)
- `0.45` (45%) for editor height (line 131)
- `500` milliseconds for focus delay — commented out (line 215)

**Fix:**
Should be named constants:

```swift
private enum Timing {
    static let keyboardDismissDelay: Duration = .seconds(0.35)
    static let cleanIndicatorDuration: Duration = .seconds(1.5)
    static let focusDelay: Duration = .milliseconds(500)
}

private enum Layout {
    static let editorHeightRatio: CGFloat = 0.45
}
```

---

### 9. Dead Code

**Location:** Line 215

```swift
// try? await Task.sleep(for: .milliseconds(500))
```

Should be removed or restored with explanation.

---

## 🟡 Potential Glitch Sources

**Likely causes of user-reported glitches (in order of probability):**

1. **Keyboard animation race condition**
   - Removing the 500ms delay means keyboard appears during sheet presentation
   - Results in visible layout jump or stutter
   - **Most likely culprit**

2. **dismissAndRun timing mismatch**
   - 0.35s may not match actual animation duration on all devices/iOS versions
   - Can cause camera preview to be visible in "narrowed" state before cover fully dismisses
   - More noticeable on slower devices

3. **GeometryReader recalculation during animation**
   - Editor height changes mid-animation when keyboard appears
   - Can cause text content to jump or resize visibly

4. **Orphaned didClean Task**
   - If user rapidly saves after cleaning, animation may glitch
   - Task outliving the view can cause state mutations post-dismissal

---

## ✅ What's Done Well

- ✅ `cleanForTeleprompter()` is thorough and well-commented
- ✅ Character limit enforcement works correctly
- ✅ Archive integration is clean
- ✅ Accessibility labels present
- ✅ Proper separation of concerns (sanitize vs clean)
- ✅ Unicode-aware whitespace handling

---

## 📋 Recommended Fixes

### Priority 1 (Stability)

1. **Store and cancel the didClean Task**
   - Prevents crashes/glitches from orphaned async work
   - Pattern already exists in codebase (RecordingPlayerView)

2. **Restore focus delay or document removal**
   - Likely root cause of glitches
   - If delay is necessary, restore it
   - If not, remove misleading comment

3. **Replace DispatchQueue with Task.sleep**
   - Modernize to Swift Concurrency
   - Enables proper cancellation
   - Clearer intent

### Priority 2 (Polish)

4. **Extract magic numbers to named constants**
   - Improves maintainability
   - Self-documenting code

5. **Consider fixed editor height instead of GeometryReader %**
   - More stable during animations
   - Reduces layout recalculation

### Priority 3 (UX)

6. **Add guard in save to show alert if truncating**
   - User should know if content was cut
   - Better than silent truncation

7. **Consolidate trimming logic**
   - Single source of truth for validation

---

## Summary

The file is functional but has timing issues that likely cause the reported glitches. The most suspect area is the keyboard focus timing — the commented-out 500ms delay appears to have been protecting against layout jumps during sheet presentation. The orphaned Task in the clean button is a stability risk that should be addressed immediately.

**No repeated code found** — helper functions are appropriately scoped and single-purpose.

**Recommended approach:** Fix Priority 1 items first, test on device, then evaluate if Priority 2/3 fixes are needed.
