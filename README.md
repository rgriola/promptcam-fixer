# promptcam-fixer

Cue Vue is a SwiftUI iOS vertical camera teleprompter app. It includes a recordings library, real-time audio metering, cinematic mode (where supported), and AF/AE lock.

## Tech stack

- **Language / UI:** Swift 6.0 (strict concurrency) + SwiftUI (`@Observable`)
- **Min iOS:** 18.0
- **Architecture:** MVVM with protocol-backed services for testability
- **Camera / video:** AVFoundation (`AVCaptureSession`, `AVCaptureMovieFileOutput`, cinematic video where available)
- **Audio metering:** `AVAudioEngine` input tap with `vDSP` (Accelerate) RMS + peak computation, route monitoring, hot-swap input selection with a user-preferred input that survives automatic route changes
- **Permissions:** AVFoundation + Photos framework
- **Persistence:** PhotoKit (`PHPhotoLibrary`) for saved recordings, UserDefaults for format + teleprompter style
- **Project generation:** XcodeGen (`project.yml`)
- **No third-party runtime dependencies.**

## Project layout

- [PromptCam/App](PromptCam/App) — app entry point, logging, theme
- [PromptCam/Models](PromptCam/Models) — `RecordingFormat`, `TeleprompterConfig`/`Geometry`, `Recording`, `ScriptArchive`
- [PromptCam/Services](PromptCam/Services) — `CameraService` (+ format / controls / recording extensions), `AudioMeterService`, `RecordingsService`, `PermissionService`, `CameraServiceProtocol`
- [PromptCam/ViewModels](PromptCam/ViewModels) — `CameraViewModel`, `RecordingsLibraryViewModel`
- [PromptCam/Views](PromptCam/Views) — top-level `CameraView`, `TeleprompterOverlayView`, plus subfolders:
  - `Camera/` — capture chrome (controls row, footer, VU meter, EV / aperture panels, layout)
  - `Sheets/` — format panel, settings, compose script, script archive, recordings library
  - `Teleprompter/` — scrolling text + adjustment panel
  - `Recordings/` — recordings library UI
  - `Components/` — reusable views (permission rows, warning banners)
- [PromptCamTests](PromptCamTests) — XCTest unit tests (165 tests)
- [PromptCamUITests](PromptCamUITests) — XCUITest smoke test

## Local setup

1. Install Xcode 27 (Swift 6.4 toolchain; Xcode 26+ also builds the project) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Optional: SwiftLint + SwiftFormat for the `.swiftlint.yml` / `.swiftformat` configs.
2. Generate the project:
   ```bash
   xcodegen generate
   ```
3. Configure code signing (required to run on a device). Signing settings are
   externalized to `Signing.xcconfig` so the repo stays portable — no personal
   Team ID is committed. Copy the template and set your Apple Developer Team ID:
   ```bash
   cp Signing.local.xcconfig.example Signing.local.xcconfig
   # edit Signing.local.xcconfig and set DEVELOPMENT_TEAM = <your team id>
   ```
   `Signing.local.xcconfig` is git-ignored and overrides the committed defaults.
   Alternatively, set the team directly in Xcode's _Signing & Capabilities_ tab.
4. Open `PromptCam.xcodeproj` and run on a device. The camera, microphone, and photo library permissions are required.

Re-run `xcodegen generate` whenever you add or delete a Swift file — the `PromptCam` and `PromptCamTests` targets use glob paths from `project.yml`.

## Running tests

```bash
xcodebuild test \
  -project PromptCam.xcodeproj \
  -scheme PromptCam \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PromptCamTests
```

Coverage focus areas:

- `DeviceCapabilitiesTests` — `isSupported`, `adjusted` clamping rules, resolution / fps queries
- `RecordingFormatTests` — UserDefaults round-trip + corruption resilience
- `TeleprompterConfigTests` / `TeleprompterGeometryTests` — config clamping + geometry math, plus the
  3-state `center → left → right → center` alignment cycle and its `TextAlignment` / SF Symbol mappings
- `CameraViewModelTests` — recording state, sheet routing, format application (via `MockCameraService`)
- `AudioMeterServiceTests` — dB → linear normalization
- `PermissionStatusDisplayTests` — label / color mapping for every permission state, including the
  distinct `Limited` Photos badge
- `CameraErrorTests` — every error case has a localized description

### Troubleshooting: `xcodebuild requires Xcode`

If `xcodebuild` fails with `tool 'xcodebuild' requires Xcode, but active developer directory
'/Library/Developer/CommandLineTools' is a command line tools instance`, the active developer
directory is pointed at the Command Line Tools rather than at Xcode. Point it at Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcode-select -p   # => /Applications/Xcode.app/Contents/Developer
```

For a one-off run without `sudo`, override it per-command instead:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test ...
```

## Notes

- Camera mutations run on a dedicated serial `sessionQueue`; `AudioMeterService` is a `final class` marked `@unchecked Sendable`, with `NSLock`-protected callback and metering state to satisfy Swift 6 strict concurrency.
- `AudioMeterService` shares the global `AVAudioSession` with `AVCaptureSession` and intentionally never calls `setActive(false)` — doing so would silence recordings.
- Audio-session interruptions are delivered via `DispatchQueue.main.async` (not `Task`) to preserve FIFO ordering, plus a sequence-number guard that discards stale deliveries. See `audio-fix.md`, Phase 0.
- The silence watchdog triggers on **peak** amplitude, taken as the max across channels. RMS cannot distinguish a quiet room from a dead mic; peak separates them by >50 dB. See `audio-fix.md`, Phase 4.
- Recordings are saved to the Photos library; the in-app library uses `PHPickerViewController`-style fetches via `PhotoKit`.
- Photo Library is the only permission with a middle state, so `.limited` surfaces as its own yellow **Limited** badge rather than collapsing into green **Granted** — users can tell full from partial access at a glance.
- Teleprompter alignment cycles through all three states (`center → left → right → center`); right alignment is kept for right-to-left languages.
