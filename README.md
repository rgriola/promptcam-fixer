# promptcam-fixer

PromptCam is a SwiftUI iOS MVP camera app with a teleprompter overlay for recording video while reading script text on screen.

## Tech stack

- **Language/UI:** Swift + SwiftUI
- **Architecture:** MVVM
- **Camera/Video:** AVFoundation (`AVCaptureSession`, `AVCaptureMovieFileOutput`)
- **Permissions:** AVFoundation + Photos framework
- **Save/Export:** PhotoKit (`PHPhotoLibrary`)
- **Teleprompter Overlay:** Native SwiftUI overlay (`ZStack`, `TimelineView`)
- **Audio:** AVAudioSession-ready via audio capture input

## Project layout

- `/tmp/workspace/rgriola/promptcam-fixer/PromptCam/App` – app entrypoint
- `/tmp/workspace/rgriola/promptcam-fixer/PromptCam/Models` – teleprompter model config
- `/tmp/workspace/rgriola/promptcam-fixer/PromptCam/Services` – camera + permissions services
- `/tmp/workspace/rgriola/promptcam-fixer/PromptCam/ViewModels` – MVVM view model
- `/tmp/workspace/rgriola/promptcam-fixer/PromptCam/Views` – camera preview and overlay views
- `/tmp/workspace/rgriola/promptcam-fixer/PromptCamTests` – XCTest unit tests
- `/tmp/workspace/rgriola/promptcam-fixer/PromptCamUITests` – XCUITest smoke test

## Local setup

1. Install Xcode, SwiftLint, SwiftFormat, and XcodeGen.
2. Generate the project:
   ```bash
   cd /tmp/workspace/rgriola/promptcam-fixer
   xcodegen generate
   ```
3. Open `PromptCam.xcodeproj` in Xcode and run on a device.

## Notes

- This MVP uses no third-party runtime dependencies.
- Recordings are saved to the Photos library after recording completes.
- Camera, microphone, and photo library permissions are required.
