# promptcam-fixer

PromptCam is a SwiftUI iOS camera app with a teleprompter overlay for recording video while reading script text on screen. Includes a recordings library, real-time audio metering, cinematic mode (where supported), and AF/AE lock.

## Tech stack

- **Language / UI:** Swift 6.0 (strict concurrency) + SwiftUI (`@Observable`)
- **Min iOS:** 18.0
- **Architecture:** MVVM with protocol-backed services for testability
- **Camera / video:** AVFoundation (`AVCaptureSession`, `AVCaptureMovieFileOutput`, cinematic video where available)
- **Audio metering:** `AVAudioEngine` input tap with `vDSP` (Accelerate) RMS computation, route monitoring, hot-swap input selection
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
- [PromptCamTests](PromptCamTests) — XCTest unit tests (73 tests)
- [PromptCamUITests](PromptCamUITests) — XCUITest smoke test

## Local setup

1. Install Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Optional: SwiftLint + SwiftFormat for the `.swiftlint.yml` / `.swiftformat` configs.
2. Generate the project:
   ```bash
   xcodegen generate
   ```
3. Open `PromptCam.xcodeproj` and run on a device. The camera, microphone, and photo library permissions are required.

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
- `TeleprompterConfigTests` / `TeleprompterGeometryTests` — config clamping + geometry math
- `CameraViewModelTests` — recording state, sheet routing, format application (via `MockCameraService`)
- `AudioMeterServiceTests` — dB → linear normalization
- `CameraErrorTests` — every error case has a localized description

## Notes

- Camera mutations run on a dedicated serial `sessionQueue`; `AudioMeterService` is a `Sendable` value type with `NSLock`-protected callback storage to satisfy Swift 6 strict concurrency.
- `AudioMeterService` shares the global `AVAudioSession` with `AVCaptureSession` and intentionally never calls `setActive(false)` — doing so would silence recordings.
- Recordings are saved to the Photos library; the in-app library uses `PHPickerViewController`-style fetches via `PhotoKit`.
