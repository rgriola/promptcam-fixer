# Share Button Flash Fix — RecordingPlayerView

## Problem

When swiping between videos in the player carousel, the Share button visibly flashes. The Close and Trash buttons do not exhibit this behavior.

## Root Cause

The flash has two contributing factors:

### 1. Structural view-type swap (primary cause)

`selectRecording` sets `activeURL = nil` synchronously on every swipe commit:

```swift
private func selectRecording(_ selected: Recording) {
    cancelInFlightResolve()
    loadFailed = false
    activeURL = nil          // ← fires immediately, triggers re-render
    activeRecording = selected
}
```

`shareButton` is a `@ViewBuilder` that branches on `activeURL`:

```swift
@ViewBuilder
private var shareButton: some View {
    if let activeURL {
        ShareLink(item: VideoFile(url: activeURL), ...) { controlIcon(..., tint: Theme.primaryText) }
    } else {
        controlIcon(..., tint: Theme.secondaryText)   // plain Image, no ShareLink wrapper
    }
}
```

When `activeURL` goes nil, SwiftUI must destroy the `ShareLink` (a system button with its own UIKit-backed view subtree) and replace it with a bare `Image`. That destroy/recreate cycle — two structurally different view types — produces the flash.

Close and Trash are always the same `Button { controlIcon(...) }` shape with a fixed tint, so they have no branch to swap and never flash.

### 2. Tint color change (secondary cause)

Simultaneously, the tint shifts from `Theme.primaryText` to `Theme.secondaryText`. SwiftUI animates this color crossfade within the same frame as the drag-commit spring animation, adding to the visual noise.

## Proposed Fix

### Fix 1 — Introduce a dedicated `shareURL` state (primary)

`activeURL` drives the player/resolve machinery and must go nil on swipe. The share button does not need to follow that lifecycle. Add a separate state variable:

```swift
@State private var shareURL: URL?
```

Set it wherever a real URL is resolved (in the `.task(id: activeRecording.id)` completion block and in `loadPlayer`). **Never** clear it in `selectRecording`.

Update `shareButton` to bind to `shareURL` instead of `activeURL`:

```swift
@ViewBuilder
private var shareButton: some View {
    if let shareURL {
        ShareLink(
            item: VideoFile(url: shareURL),
            preview: SharePreview(activeRecording.formattedDuration)
        ) {
            controlIcon("square.and.arrow.up.circle.fill", tint: Theme.primaryText)
        }
    } else {
        controlIcon("square.and.arrow.up.circle.fill", tint: Theme.secondaryText)
    }
}
```

During the swipe transition window, `shareURL` still holds the previous video's URL so the `ShareLink` branch never tears down — no structural swap, no flash. By the time controls become interactive again (animation settled, new URL resolved for local files), `shareURL` will have updated to the new video's URL.

### Fix 2 — Suppress tint-change animation on the share button (supporting)

Apply `.animation(nil, value: shareURL)` at the call site in `topBar` to prevent SwiftUI from crossfading the tint when `shareURL` changes:

```swift
// In topBar HStack:
shareButton
    .animation(nil, value: shareURL)
```

## Files to Change

- `PromptCam/Views/Recordings/RecordingPlayerView.swift`
  - Add `@State private var shareURL: URL?` alongside `activeURL`
  - Set `shareURL = url` in the `.task(id: activeRecording.id)` resolve block
  - Set `shareURL = url` at the end of `loadPlayer()` (or wherever `activeURL` receives a real value)
  - Update `shareButton` to read `shareURL` instead of `activeURL`
  - Add `.animation(nil, value: shareURL)` on `shareButton` in `topBar`
