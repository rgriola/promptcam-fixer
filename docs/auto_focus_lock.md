# Auto Focus Lock — Face Tracking in Auto Mode

**Date Created:** June 7, 2026  
**Status:** Planning Phase  
**Estimated Effort:** 2-3 hours implementation + testing

## Goal

Add continuous face detection and tracking visualization when camera is in Auto Mode. Show dynamic green rectangles around detected faces that update in real-time, replacing the static center-on-startup indicator.

---

## Current State

- Focus indicator: Fixed 80x80 yellow rectangle shown on manual tap/lock
- No face detection infrastructure
- Center indicator shown on camera start for 3 seconds, then fades
- Manual tap focus: Shows yellow rectangle at tap point
- Lock mode: Shows yellow rectangle at locked focus point

---

## Desired UX Behavior

### Auto Mode (lockStatus == .auto)

- **Continuous green rectangles** around all detected faces
- Updates in real-time as faces move/enter/exit frame
- No fade-out (stays visible as long as faces detected)
- Multiple faces: Show all simultaneously
- No faces: No indicator shown

### Manual Focus (tap to focus, not locked)

- Yellow rectangle at tapped point
- Fades after 3 seconds
- Temporarily hides face tracking

### Locked Mode (lockStatus != .auto)

- Yellow rectangle at locked focus point
- Persistent (doesn't fade)
- Face tracking hidden

---

## Implementation Plan

### Phase 1: CameraService — Add Face Detection

**File:** `PromptCam/Services/CameraService.swift`

#### Step 1.1: Add Properties

```swift
// Near top with other properties
private let metadataOutput = AVCaptureMetadataOutput()
private let metadataQueue = DispatchQueue(label: "com.rgriola.promptcam.metadata")
var onFacesDetected: (([CGRect]) -> Void)?
```

#### Step 1.2: Configure Metadata Output in `configureSession()`

Inside `configureSession()` after adding movie output, before `commitConfiguration()`:

```swift
// Add metadata output for face detection
if session.canAddOutput(metadataOutput) {
    session.addOutput(metadataOutput)

    // Must be called AFTER addOutput
    if metadataOutput.availableMetadataObjectTypes.contains(.face) {
        metadataOutput.metadataObjectTypes = [.face]
        metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)
    } else {
        print("[Face] Face detection not available on this device")
    }
} else {
    print("[Face] Cannot add metadata output")
}
```

#### Step 1.3: Implement AVCaptureMetadataOutputObjectsDelegate

Add extension at bottom of file:

```swift
// MARK: - Face Detection
extension CameraService: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        // Filter to face objects only
        let faceObjects = metadataObjects.compactMap { $0 as? AVMetadataFaceObject }

        // Extract bounds (in normalized coordinates 0-1)
        let faceBounds = faceObjects.map { $0.bounds }

        // Publish to main thread
        DispatchQueue.main.async {
            self.onFacesDetected?(faceBounds)
        }
    }
}
```

**Note:** Face bounds are in **normalized coordinates** (0-1 range). Must convert to view coordinates in CameraView using GeometryReader.

---

### Phase 2: CameraViewModel — Publish Face Data

**File:** `PromptCam/ViewModels/CameraViewModel.swift`

#### Step 2.1: Add Published Property

```swift
// Near other @Published properties around line 50-70
@Published var detectedFaces: [CGRect] = []
```

#### Step 2.2: Bind Callback in `bindCallbacks()`

Inside `bindCallbacks()` method (around line 90-120):

```swift
cameraService.onFacesDetected = { [weak self] faces in
    self?.detectedFaces = faces
}
```

#### Step 2.3: Clear Faces on Stop

Inside `onDisappear()` method:

```swift
func onDisappear() {
    cameraService.stopSession()
    detectedFaces = []  // Clear face data when camera stops
}
```

---

### Phase 3: FocusIndicatorView — Support Face Rectangles

**File:** `PromptCam/Views/FocusIndicatorView.swift`

#### Current Implementation:

- Single point indicator
- Fixed 80x80 size
- Yellow color only

#### New Requirements:

- Support multiple rectangles
- Dynamic sizing based on face bounds
- Color parameter (green for auto, yellow for manual/lock)
- Coordinate conversion from normalized (0-1) to view coordinates

#### Step 3.1: Update View Signature

Replace current implementation (~20 lines) with:

```swift
// May [DATE] - [TIME] - GitHub Copilot (GPT-5.3-Codex)
import SwiftUI

/// Visual focus indicator overlay supporting both manual focus (single point)
/// and face tracking (multiple rectangles).
struct FocusIndicatorView: View {
    /// Display mode: manual tap/lock vs. face tracking
    enum Mode {
        case manual(point: CGPoint)      // Single yellow rectangle at fixed point
        case faceTracking(faces: [CGRect])  // Green rectangles around faces (normalized coords)
    }

    let mode: Mode
    let viewSize: CGSize  // GeometryReader proxy size for coordinate conversion

    var body: some View {
        switch mode {
        case .manual(let point):
            // Single 80x80 yellow rectangle at tapped/locked point
            Rectangle()
                .strokeBorder(Theme.yellow, lineWidth: 2)
                .frame(width: 80, height: 80)
                .position(point)

        case .faceTracking(let faces):
            // Green rectangles around detected faces
            ForEach(Array(faces.enumerated()), id: \.offset) { _, normalizedRect in
                let viewRect = convertNormalizedToView(normalizedRect)
                Rectangle()
                    .strokeBorder(Theme.green, lineWidth: 2)
                    .frame(width: viewRect.width, height: viewRect.height)
                    .position(x: viewRect.midX, y: viewRect.midY)
            }
        }
    }

    /// Converts AVFoundation normalized coordinates (0-1) to view pixel coordinates.
    /// AVFoundation origin is bottom-left, SwiftUI origin is top-left.
    private func convertNormalizedToView(_ normalized: CGRect) -> CGRect {
        let x = normalized.origin.x * viewSize.width
        let y = (1 - normalized.origin.y - normalized.height) * viewSize.height  // Flip Y
        let width = normalized.width * viewSize.width
        let height = normalized.height * viewSize.height

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
```

---

### Phase 4: CameraView — Integrate Face Tracking

**File:** `PromptCam/Views/CameraView.swift`

#### Step 4.1: Update Focus Indicator Layer (Layer 2)

Current code (around line 104-109):

```swift
// Layer 2: Focus reticle shown after tap/lock
if showFocusIndicator, let focusIndicatorPoint {
    FocusIndicatorView(point: focusIndicatorPoint)
        .allowsHitTesting(false)
        .transition(.opacity)
}
```

**Replace with:**

```swift
// Layer 2: Focus indicator — manual tap/lock or face tracking
ZStack {
    // Show face tracking in Auto Mode when not manually focusing
    if viewModel.lockStatus == .auto && !showFocusIndicator && !viewModel.detectedFaces.isEmpty {
        FocusIndicatorView(
            mode: .faceTracking(faces: viewModel.detectedFaces),
            viewSize: proxy.size
        )
        .allowsHitTesting(false)
    }

    // Show manual focus indicator on tap/lock (overrides face tracking)
    if showFocusIndicator, let focusIndicatorPoint {
        FocusIndicatorView(
            mode: .manual(point: focusIndicatorPoint),
            viewSize: proxy.size
        )
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
```

#### Step 4.2: Remove Center-on-Startup Indicator

Currently in `.onAppear` (around line 267-272):

```swift
.onAppear {
    viewModel.onAppear()
    // Show focus feedback at center after brief delay on camera start
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        showCenterFocusFeedback()
    }
}
```

**Replace with:**

```swift
.onAppear {
    viewModel.onAppear()
    // Face tracking will show automatically in Auto Mode
}
```

Can delete `showCenterFocusFeedback()` method if only used on startup.

#### Step 4.3: Update Lock Toggle Logic

In `toggleLockStatus()` (around line 433-443):

Currently shows indicator at last focus point when locking. Keep this behavior — manual lock indicator should persist and override face tracking.

**No changes needed** — existing logic already prioritizes `showFocusIndicator` over face tracking.

---

## Testing Checklist

### Device Testing (iPhone/iPad with front camera)

- [ ] **Auto Mode baseline:**
  - [ ] Launch camera → face tracking shows immediately (green rectangles)
  - [ ] Move face around → rectangles follow smoothly
  - [ ] Multiple faces → all tracked simultaneously
  - [ ] Face exits frame → rectangle disappears
  - [ ] No faces → no indicator shown

- [ ] **Manual tap focus:**
  - [ ] Tap preview → yellow rectangle at tap point
  - [ ] Face tracking hidden during manual focus
  - [ ] After 3 seconds → yellow fades, face tracking returns

- [ ] **Lock toggle:**
  - [ ] Tap AUTO badge → locks at last focus point
  - [ ] Badge shows AF/AE (green)
  - [ ] Yellow rectangle persists at locked point
  - [ ] Face tracking hidden while locked
  - [ ] Tap AF/AE badge → unlocks to AUTO (green)
  - [ ] Face tracking returns immediately

- [ ] **Edge cases:**
  - [ ] Start camera with face in frame → tracking shows immediately
  - [ ] Start camera with no face → no indicator, works when face enters
  - [ ] Switch between front/back camera (if supported)
  - [ ] Teleprompter overlay → face tracking not blocked
  - [ ] Lock → switch mode → unlock → face tracking still works

### Simulator Testing

**Note:** Simulator does not support face detection. Test with physical device only.

---

## Color Scheme

From `Theme.swift`:

```swift
static let green = Color(hex: "00C853")   // Face tracking in Auto Mode
static let yellow = Color(hex: "FFD600")  // Manual focus/lock indicator
```

---

## Performance Considerations

1. **Metadata frequency:** AVFoundation calls delegate at ~30 Hz
   - Consider throttling updates if performance issues (DispatchQueue debounce)
2. **ForEach rendering:** Multiple face rectangles create multiple views
   - SwiftUI handles this efficiently for <10 faces
   - Use `id: \.offset` for array enumeration (faces don't have stable IDs)

3. **Coordinate conversion:** `convertNormalizedToView()` runs on every face, every frame
   - Already optimized (simple math, no allocations)

---

## Known Limitations

1. **Face detection accuracy:**
   - Works best with good lighting
   - May not detect faces at extreme angles
   - Sunglasses/masks reduce detection reliability

2. **No face detection on simulator:**
   - Must test on physical device
   - Face metadata not available in simulator

3. **Device support:**
   - Face detection available on all iOS devices with camera
   - Older devices (pre-iPhone 5s) may have reduced performance

---

## Future Enhancements (Out of Scope)

- [ ] Fade animation when faces enter/exit frame
- [ ] Different colors for focused vs. unfocused faces
- [ ] Face smile detection (`hasSmile` property on `AVMetadataFaceObject`)
- [ ] Auto-capture when face detected + smile
- [ ] Face roll/yaw angles for 3D-style tracking
- [ ] Persistent face ID tracking across frames (not supported by AVFoundation)

---

## Code References

### AVFoundation Face Detection Docs

- `AVCaptureMetadataOutput`: [Apple Docs](https://developer.apple.com/documentation/avfoundation/avcapturemetadataoutput)
- `AVMetadataFaceObject`: [Apple Docs](https://developer.apple.com/documentation/avfoundation/avmetadatafaceobject)
- Coordinate spaces: [Vision Programming Guide](https://developer.apple.com/documentation/vision/understanding_coordinate_spaces)

### Related Files

- `PromptCam/Services/CameraService.swift` — Camera session management
- `PromptCam/ViewModels/CameraViewModel.swift` — Published state
- `PromptCam/Views/FocusIndicatorView.swift` — Visual indicator
- `PromptCam/Views/CameraView.swift` — View composition + gesture handling
- `PromptCam/App/Theme.swift` — Color constants

---

## Implementation Order

1. **Phase 1** (CameraService) — Add metadata output, delegate
2. **Phase 2** (CameraViewModel) — Publish face data
3. **Test:** Print detected faces in console
4. **Phase 3** (FocusIndicatorView) — Update to support modes
5. **Phase 4** (CameraView) — Integrate face tracking display
6. **Test:** Full device testing checklist
7. **Polish:** Remove center-on-startup code if no longer needed

---

## Git Commit Strategy

```bash
# Commit 1: CameraService face detection infrastructure
git add PromptCam/Services/CameraService.swift
git commit -m "Add face detection metadata output to CameraService"

# Commit 2: ViewModel face data publishing
git add PromptCam/ViewModels/CameraViewModel.swift
git commit -m "Publish detected faces from CameraViewModel"

# Commit 3: FocusIndicatorView redesign
git add PromptCam/Views/FocusIndicatorView.swift
git commit -m "Update FocusIndicatorView to support face tracking mode"

# Commit 4: CameraView integration
git add PromptCam/Views/CameraView.swift
git commit -m "Integrate face tracking display in Auto Mode"

# Commit 5: Cleanup (if applicable)
git add PromptCam/Views/CameraView.swift
git commit -m "Remove center-on-startup indicator (replaced by face tracking)"
```

---

## Notes

- Keep existing manual focus behavior unchanged
- Face tracking is **additive** — doesn't replace tap-to-focus
- Lock mode behavior unchanged — persists across mode switches
- Green = Auto (face tracking), Yellow = Manual/Lock (current behavior)
