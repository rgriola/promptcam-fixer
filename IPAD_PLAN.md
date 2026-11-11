# iPad Support Plan

## Goal

Make Cue Vue a native, usable iPad app while preserving the existing iPhone experience. This includes adapting the camera and teleprompter UI to iPad sizes and orientations, keeping preview and recording orientation correct, and handling iPad multitasking and external displays.

This is a plan only; no implementation changes are included here.

## Current state and constraints

- The `PromptCam` app target in [`project.yml`](./project.yml) sets `TARGETED_DEVICE_FAMILY` to `"1"` (iPhone only), overriding the shared `"1,2"` setting. iPad therefore runs the iPhone app in compatibility mode rather than receiving a native iPad layout.
- The project sets an iPhone portrait orientation but does not define an iPad orientation setting.
- [`CameraLayout.swift`](./PromptCam/Views/Camera/CameraLayout.swift) calculates a 9:16 preview from the container width and gives the remaining height to controls. On an iPad this can leave little or no room for those controls, especially in landscape.
- The camera screen in [`CameraView.swift`](./PromptCam/Views/CameraView.swift) layers the preview, controls, teleprompter, and panels around this phone-oriented layout.
- Several supporting views use fixed dimensions. Examples include the teleprompter viewport, VU meter, onboarding content, and recording carousel/player.
- The camera preview uses `AVCaptureVideoPreviewLayer`, but the current code does not configure video rotation for the preview or movie output. iPad rotation support must account for both what the user sees and the orientation of saved recordings.
- The Info.plist enables multiple scenes and configures a separate external-display scene. iPad multi-window behavior and external-display behavior should be considered together, without assuming that the external-display scene requires multiple main app windows.
- [`AV_FROZEN_CAMERA_FIX.md`](./docs/AV_FROZEN_CAMERA_FIX.md) already documents camera unavailability when multiple foreground apps use the camera. Treat this as a user-initiated multitasking condition; do not automatically restart the camera in response.
- A GitHub Actions workflow already exists in [`.github/workflows/ci.yml`](./.github/workflows/ci.yml). It runs lint/format checks and unit tests on an iPhone simulator for pull requests, pushes to `main`/`master`, and manual runs. It does not currently run iPad UI tests. Its presence is not proof of a successful CI baseline; verify a real run before making checks required.

## Decisions to make before implementation

1. **Recording orientation and shape:** Should recordings remain portrait 9:16, follow the device orientation, or offer a user choice? Preview sizing and teleprompter placement depend on this.
2. **Supported orientations:** Which orientations should the iPad app support? Plan for rotation and changing window sizes, including when a user resizes a Stage Manager window.
3. **Teleprompter placement:** Many recent iPads place the front-facing camera on a landscape edge. Decide how the script should be positioned relative to the camera in landscape and portrait.
4. **Small windows and multitasking:** Should the app retain a compact, phone-style layout in Split View and small windows, or ask the user to enlarge the window when the camera experience cannot fit?
5. **Multiple main windows:** Should users be allowed to open more than one Cue Vue camera window? If not, define how the app prevents or handles competing capture sessions while preserving the external-display scene.
6. **Minimum supported iPad:** Identify the oldest supported iPad. Camera availability, formats, cinematic features, and Center Stage support differ by hardware.
7. **Center Stage:** Decide whether to disable or lock Center Stage for consistent teleprompter framing, or expose a user-facing control.

## Implementation plan

### 0. Establish and extend GitHub Actions CI

Establish a passing CI baseline before the iPad refactor so later changes have automated regression protection. Extend the existing workflow rather than introduce a competing workflow.

#### Baseline setup

- Verify that GitHub Actions is enabled and run the existing workflow against the current default branch. Record any pre-existing failures separately from failures introduced by iPad work; do not disable checks just to obtain a green result.
- Select a verified macOS runner and pin the Xcode version and build tools. The source uses iOS 26 AVFoundation APIs, so CI needs an Xcode 26-or-newer toolchain with the corresponding SDK even though the deployment target remains iOS 18. Runtime availability checks do not make those APIs compile with an older SDK.
- Log the Xcode version, available SDKs, and available simulator runtimes to make runner changes diagnosable.
- Regenerate the Xcode project with XcodeGen from `project.yml` on each run. Simulator builds must not depend on local signing overrides or developer-machine settings.
- Use unsigned simulator builds/tests with `CODE_SIGNING_ALLOWED=NO` and `CODE_SIGNING_REQUIRED=NO`. The initial CI scope does not include App Store distribution and should not require signing certificates, provisioning profiles, or App Store credentials.
- Preserve the existing SwiftLint and SwiftFormat checks using the repository's configuration.

#### Check coverage and rollout

| Check | When to run | Purpose |
|---|---|---|
| Lint and formatting | Pull requests and default-branch pushes | Preserve the existing code-quality checks. |
| Simulator build and unit tests | Pull requests and default-branch pushes | Catch compilation, strict-concurrency, configuration, and behavioral regressions. Keep the existing iPhone lane. |
| iPad UI smoke tests | Manual initially; required on pull requests once stable and native iPad support is enabled | Confirm launch, orientation changes, and access to essential camera controls on a representative iPad simulator. |
| Expanded iPad UI matrix | Scheduled and manual runs | Cover additional iPad sizes, portrait/landscape layouts, Dynamic Type, sheets, and supported window configurations without making every pull request unnecessarily expensive. |

- Resolve installed simulators explicitly by runtime and device identifier. Fail with useful diagnostics if no suitable device exists rather than silently skip the tests.
- Start unit tests serially because some existing tests use shared preferences, notifications, and timing-sensitive asynchronous behavior. Introduce parallel execution only after isolation is verified.
- Add layout unit tests alongside the adaptive layout implementation. Assert that the preview and controls fit within the available bounds and safe areas at representative compact, portrait, and landscape sizes.
- Extend the current UI test coverage beyond launch/control presence. Verify that record, format, lock, and teleprompter controls remain visible and reachable after rotation; test sheet dismissal and larger text sizes.
- Run UI tests through the existing test entry path without requiring physical camera access. Passing these tests verifies UI behavior, not successful real-world video recording.
- Automate window resizing only where simulator/test-runner support is reliable. Keep unsupported multitasking scenarios in the physical-device QA matrix.

#### Failure reporting and merge protection

- Retain `xcodebuild` failure exit codes when formatting logs. Cancel superseded runs for the same pull request, set job timeouts, and keep workflow permissions limited to what the jobs need.
- Upload `.xcresult` bundles, relevant logs, and UI-test screenshots when available, especially on failure. Use bounded artifact retention.
- After successful baseline and pull-request runs, configure branch protection or repository rulesets to require the stable lint, build/unit-test, and iPad smoke checks before merging.
- Consider the CI phase complete when a pull request demonstrates passing required checks, failures provide actionable artifacts, and the required-check rules prevent merging a failing change.

#### Limits of CI

Simulator CI does not certify iPad compliance by itself. Physical iPads remain necessary to validate camera selection and capabilities, preview/saved-video rotation, actual recording, audio synchronization and microphone routing, interruptions, Photos saves, external displays, multitasking camera availability, and sustained thermal/performance behavior.

### 1. Enable native iPad availability

- Change the app target's `TARGETED_DEVICE_FAMILY` in `project.yml` to include iPad, then regenerate the Xcode project using the project's XcodeGen workflow.
- Add an iPad-specific supported-orientations setting that matches the decision above. Keep the existing iPhone orientation behavior unless changing it is part of the product decision.
- Verify the generated project settings in both Debug and Release. Check the app icon, launch screen, permissions onboarding, and first launch on an iPad.
- Expect the existing layout to look wrong at this stage; this step only makes native iPad testing possible.

### 2. Establish adaptive camera layout modes

Refactor the layout around the available window size rather than treating the screen as a tall phone:

- **Compact:** Preserve today's iPhone composition. Reuse it for narrow iPad windows when the controls remain usable.
- **Regular portrait:** Fit the preview into the available height after reserving space for camera controls; center or otherwise balance the preview and controls.
- **Regular landscape:** Give the preview the main area and move recording, audio, and utility controls into a side rail or another layout designed for landscape.

Specific work:

- Replace the width-only calculation in `CameraLayout.previewFrame` with a calculation that considers available width, available height, safe areas, selected recording shape, and the space required by controls.
- Make the controls container arrange its content horizontally or vertically based on the selected layout mode.
- Review fixed control dimensions and spacing. Keep touch targets accessible while using available iPad space without stretching controls across the whole screen.
- Keep panels and other overlays within the usable window bounds, including safe areas.
- Add unit tests for layout selection and geometry covering iPhone, iPad portrait, iPad landscape, and a compact/resized window.

### 3. Make capture orientation reliable

- Use `AVCaptureDevice.RotationCoordinator` to keep the preview upright as device orientation changes and to set the movie output connection's rotation for recording.
- Define when orientation is sampled and whether it is locked for the duration of a recording. Avoid changing the file orientation midway through a take.
- Verify tap-to-focus and exposure coordinate conversion after rotating the preview.
- Check external-display video orientation and saved-file orientation against the same product decision.
- Test front-camera discovery and available formats across the minimum supported iPads. Do not assume every iPad has TrueDepth, cinematic capture, or the same front-camera resolutions.
- Decide and test the interaction with Center Stage, if available.

### 4. Adapt the teleprompter

- Derive the teleprompter viewport from the preview and window geometry instead of a fixed 475-point height.
- Set a readable maximum line width so script text does not span an entire large iPad display.
- Tune text size, margins, and scroll speed for typical iPad reading distances.
- Place the script near the front camera for each supported orientation and hardware camera position.
- Verify that the script remains legible and that controls do not cover it in compact, portrait, landscape, and resized-window layouts.

### 5. Adapt panels, sheets, library, player, and onboarding

- **Camera panels:** Give panels a sensible maximum width on iPad or consider button-anchored popovers where that improves the interaction. Avoid full-window controls for settings that are better presented as a bounded panel.
- **Sheets:** Review the camera settings, script archive, compose, and recordings presentations on iPad. Choose form, page, or full-screen sizing intentionally; do not rely on iPhone sheet behavior. The project targets iOS 18, so use presentation APIs supported by that deployment target.
- **Recordings library:** Rework carousel sizing for wide windows and decide whether an iPad grid is preferable. Preserve useful focus and selection behavior.
- **Recording player:** Review the player in portrait, landscape, and resized windows. Replace phone-specific fixed widths where they prevent effective use of iPad space.
- **Onboarding and instructions:** Center content within a readable maximum width and confirm it fits in landscape and smaller windows.
- Check settings, alerts, menus, and permission prompts for layout clipping and dismissibility on iPad.

### 6. Handle multitasking and scene lifecycle

- Handle `videoDeviceNotAvailableWithMultipleForegroundApps` as a camera-unavailable condition caused by multitasking. Show clear recovery guidance and do not automatically restart the capture session; this is consistent with [`AV_FROZEN_CAMERA_FIX.md`](./docs/AV_FROZEN_CAMERA_FIX.md).
- Test camera start, interruption, recovery, and app foreground/background transitions in Split View, Slide Over, and Stage Manager configurations supported by the OS and hardware.
- Make the main-window policy explicit. Ensure scene lifecycle and camera ownership do not allow competing windows to start conflicting capture sessions.
- Resize the window during use and confirm the preview and controls recompute without clipping or becoming unreachable.
- Test extended external display separately from display mirroring, preserving the existing clean-output behavior.

### 7. Review device-specific wording and capabilities

- Replace user-facing references to “iPhone mic” in `AudioMeterViewModel` with wording appropriate to the current device or active audio route.
- Review the device-name mapping in `DeviceModel.swift` for the supported iPad models. Prefer capability checks for behavior; model names should not be required for camera support.
- Extend `DeviceCapabilitiesTests` with representative iPad camera, format, and feature combinations.

### 8. Validate and prepare release assets

- Add iPad-specific cases to the existing UI and QA test coverage, including [`PHASE6_QA_MATRIX.md`](./docs/PHASE6_QA_MATRIX.md).
- Test on at least one iPad mini, one 11-inch iPad, and one 13-inch iPad where available. Cover portrait and landscape, full-size and compact windows, and a model with a landscape-edge front camera.
- Verify saved video orientation, preview orientation, audio selection, teleprompter readability, external-display output, and recovery from camera interruptions.
- Review iPad App Store screenshots and metadata after the UI is stable.
- Run the CI simulator lanes and expanded iPad test matrix, then perform hardware acceptance tests for camera, audio routing, and rotation. Require both passing CI and physical-device sign-off before release.

## Suggested sequencing

1. Decide the product questions above, especially recording shape/orientation and small-window behavior.
2. Establish the passing GitHub Actions lint/build/unit-test baseline before changing the app.
3. Enable native iPad availability and add the initial iPad simulator UI smoke lane.
4. Implement and verify capture rotation before finalizing preview geometry.
5. Build the adaptive camera layout and teleprompter placement, adding geometry and UI regression tests alongside the changes.
6. Adapt the library, player, sheets, panels, and onboarding; expand the scheduled/manual iPad matrix.
7. Complete multitasking, external-display, capability, hardware regression, and App Store validation. Promote stable CI checks to required merge checks.

## Main delivery risks

- The camera composition is currently designed around a portrait phone; enabling iPad support alone will not make it usable.
- Rotation affects the preview, focus/exposure mapping, saved video, and external display, so those paths must be tested together.
- The teleprompter's placement must account for iPad front-camera locations, not just screen dimensions.
- iPad multitasking can make the camera unavailable or change the app's window size during a session. The app must handle these states explicitly and preserve the existing no-auto-restart behavior.
- Runner/toolchain drift and timing-sensitive tests can undermine confidence in CI. Pin the tested environment, keep tests deterministic, and do not treat simulator success as a substitute for physical-iPad acceptance.
