# Walkthrough: Unified Permissions Onboarding Page

## Summary

Consolidated all three permission requests (camera, microphone, photo library) onto a single onboarding page that gates entry to the camera view. Previously, permissions were scattered: camera+mic on launch, photo library lazily on first save.

## Changes Made

### New File

- [PermissionsOnboardingView.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/PermissionsOnboardingView.swift) — Light-themed full-screen onboarding with:
  - Three permission rows (Camera 🔵, Microphone 🟠, Photo Library 🟢) each with icon, description, and live status badge
  - "Grant Permissions" button that serially requests all not-determined permissions
  - "Continue" button enabled once Camera + Mic are granted
  - "Settings" link on denied rows to open iOS Settings
  - `scenePhase` listener to refresh statuses when returning from Settings

### Modified Files

| File                                                                                                                             | Changes                                                                                                                                                                                                                                                                                                   |
| -------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [PermissionService.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/PermissionService.swift) | Added `cameraStatus`, `microphoneStatus`, `photoLibraryStatus` getters; `allPermissionsGranted` and `cameraAndMicGranted` computed properties; individual `requestCameraAccess()`, `requestMicrophoneAccess()`, `requestPhotoLibraryAccess()` methods; changed photo scope from `.addOnly` → `.readWrite` |
| [PromptCamApp.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/App/PromptCamApp.swift)                | Root view now checks `@AppStorage("hasCompletedOnboarding")` — shows onboarding on first launch, camera directly after                                                                                                                                                                                    |
| [CameraViewModel.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/ViewModels/CameraViewModel.swift)   | Removed `showPermissionsAlert` property; `onAppear()` now goes straight to `configureSession` + `startSession` (no async permission check)                                                                                                                                                                |
| [CameraView.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Views/CameraView.swift)                  | Removed "Permissions Required" `.alert` modifier                                                                                                                                                                                                                                                          |
| [CameraService.swift](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam/Services/CameraService.swift)         | `saveRecordingToPhotoLibrary` now guards on current status instead of calling `requestAuthorization` inline; uses `.readWrite`                                                                                                                                                                            |
| [project.yml](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/project.yml)                                            | Changed `NSPhotoLibraryAddUsageDescription` → `NSPhotoLibraryUsageDescription`                                                                                                                                                                                                                            |
| [project.pbxproj](file:///Users/rodczaro/Desktop/00-Vibecode/promptcam-fixer/PromptCam.xcodeproj/project.pbxproj)                | Same plist key update in both Debug/Release configs; registered new `PermissionsOnboardingView.swift`                                                                                                                                                                                                     |

## Design Decisions

1. **Show once** — `@AppStorage("hasCompletedOnboarding")` persists the flag. After tapping Continue, the onboarding page never shows again.
2. **Photo library `.readWrite`** — Enables users to browse/select videos for review within the app.
3. **Light theme** — Uses system colors (`Color(.systemBackground)`, `Color(.secondarySystemBackground)`) for a clean, lighter appearance.
4. **Continue after cam+mic** — Photo library is recommended but not required to enter the camera.

## Verification

- **Build**: `xcodebuild -scheme PromptCam -destination 'platform=iOS Simulator,name=iPhone 17' build` → **BUILD SUCCEEDED** ✅
- Manual testing on device recommended for permission flow validation (see implementation plan verification section).
