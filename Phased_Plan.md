May 31, 2026 - 1:00am - GitHub Copilot (Claude Opus 4.7)
Updated: June 1, 2026 - 12:25am - Antigravity (Claude Opus 4.6)

# PromptCam Phased Development Plan

Date: May 31, 2026 1:00am

## Overview

This plan aligns to the requested order of work and the Q1–Q3 guidance. Each phase includes milestones, acceptance criteria, and test coverage.

## Phase 0 — Style System + Project Hygiene (Completed)

Milestone: PromptCam styling standards locked + Theme scaffolding ready.

Checklist (Done)

- Update STYLING_GUIDE.md for PromptCam: even-number font sizes only; project-specific token rules.
- Add Theme.swift (fonts, colors, spacing, radii, icon sizes).
- Replace inline fonts/colors/radii in existing views with Theme tokens.
- Add placeholder icon tokens for upcoming nav bar controls.

Acceptance criteria (Met)

- No .font(.system(size:)) or raw colors in views.
- All existing screens render identically (no UI regressions).

Tests (Pending)

- Unit: validate TeleprompterConfig.default and clamping (existing).
- UI: smoke test to confirm camera view renders with Theme tokens.

## Phase 1 — Camera Main View (Completed)

Milestone: Selfie camera mimics iOS native camera controls using the iPhone17 reference.

Checklist (Done)

- Default to selfie camera (portrait).
- Add top-left record format panel (tappable to open settings stub).
- Keep only the native-like controls; remove the "XXXX" areas for future nav bar.

- Add touch AF/AE target indicator (visual only for now if needed).
- Add touch focus/exposure behavior with long-press lock and drag exposure adjustment.
- Ensure EV value is synced between header and focus indicator.

Acceptance criteria (Met)

- Selfie camera is default and persistent.
- Format panel visible and tappable.
- "XXXX" space stays empty/reserved.

Tests (Partially Met)

- UI: smoke test covers record button presence, format panel visibility, and AUTO lock status text.
- Unit: lock outcome decision matrix is covered in CameraService tests.
- Unit: camera default selection logic (front preferred, back fallback, unavailable) is covered in CameraService tests.
- Pending: UI-level selfie-default assertion on first launch.

Phase 1 Exit Checklist — AE/AF Reliability (No-Code)

- Tap on preview sets focus/exposure target and shows reticle.
- Long-press directly on preview target area attempts lock (native behavior), not on reticle overlay.
- Lock status appears only after capability check and successful camera configuration.
- Front camera fallback: if full AF+AE lock is unavailable, support AE-only lock with explicit status text.
- If lock is unsupported, remain in AUTO and show short unsupported status text (no false lock signal).
- Unlock flow restores continuous auto modes and updates status text immediately.
- EV value remains in sync between header and focus indicator during tap, lock, unlock, and drag.
- Exposure drag remains smooth and stable without excessive camera configuration calls.
- Focus-hide timers/debounce work items are canceled safely on view disappearance.
- Keep print("Specific Message") instrumentation for button/panel wiring during Xcode validation.

Phase 1 Reliability Test Criteria

- Manual: back camera tap focus at center and edges updates target and EV text.
- Manual: long-press at multiple points reliably enters lock state and keeps lock while finger lifts.
- Manual: front camera long-press shows AE LOCK fallback (or AUTO unsupported) correctly.
- Manual: drag exposure while locked/unlocked maintains consistent EV and does not desync UI state.
- Manual: background/foreground app during lock and exposure drag does not leave stale lock indicators.
- Manual: rapid tap/long-press sequence for 30 seconds does not create stuck lock state.
- UI test target: long-press on preview changes visible lock status text.
- UI test target: EV text updates when exposure drag is performed.
- Unit test target: lock mode decision matrix (AF+AE lock, AE-only lock, unsupported).
- Unit test target: lock state transitions and unlock return to AUTO.

Phase 1 Implementation Status Update (May 30, 2026)

- Done: long-press lock moved to preview target area (native interaction path).
- Done: lock status UX added (AUTO, AE/AF LOCK, AE LOCK, AF LOCK, LOCK UNAVAILABLE).
- Done: fallback lock mode support wired via capability matrix in camera service.
- Done: CameraView split into focused subviews inside the same file for easier maintenance.
- Done: header/footer layout polish completed and validated on iPhone 13 + iPhone 17 devices.
- Done: test updates added for lock outcome matrix + camera UI smoke assertions.
- Done: startup/record reliability improved by gating record action on camera session readiness.
- Done: footer/header actions are wired to real feature routes (photo picker, compose sheet, settings sheet, format sheet).
- Remaining: none for Phase 1.

Phase 1 Closeout Notes (Wiring Readiness)

- Camera layout baseline is now approved for wiring work.
- Header/footer controls are visually placed and stable for next-phase interaction wiring.
- Record/scroll cluster behavior is kept stable while wiring proceeds around it.
- Camera startup path now prioritizes camera+mic bring-up; photo permission is requested at save time.

CameraView Subview Decomposition Map (Phased)

Phase 1 — Split Now

- CameraPreviewSurfaceView: preview rendering + tap/long-press gesture capture.
- FocusExposureOverlayView: reticle + EV slider visualization + drag callbacks.
- CameraTopControlsView: EV pill, format panel, and top status row.
- RecordingClusterView: shutter + script scroll control cluster.
- CameraLockStatusBadgeView: explicit AUTO / AE LOCK / AE-AF LOCK status text.

\*\*\* (do not remove RG 5/30 - AE Lock, EV slider bar need adjustments, Visual Notice AE/AF is on)

Phase 2 — Split Next (Header/Nav Framing)

- CameraHeaderFrameView: top safe-area framing/styling shell.
- CameraFooterFrameView: reserved nav-area shell with spacing contracts.
- CameraChromeLayoutView: shared layout metrics for header/footer balance.

Phase 3 — Compose + Script Overlay Mode

- ComposeScriptPanelView: edit/paste script UI.
- CameraModeToggleView: compose/scroll mode switching.

Phase 4 — Scroll Controls Panel

- ScrollControlsDrawerView: speed, font size, color, opacity controls.
- ScrollControlsTabView: bottom-right open/close handle.

Phase 5 — Overlay Positioning + Safe Marker

- OverlayPositionHandleView: right-lane drag handle and persistence hooks.
- SafeMarkerOverlayView: visual marker and intensity control.

Phase 6 — Profile / Settings

- CameraSettingsEntryView: camera shell entry point.
- ProfileSettingsView: app metadata + permission status mapping.

## Phase 2 — Nav Bar + Header Frame (In Progress)

Milestone: Camera UI framed with top header and bottom nav bar space.

Checklist (In Progress)

- Done: top header container is in place and safe-area aligned.
- Done: bottom nav/footer container is in place and safe-area aligned.
- Done: replace print stubs with real action wiring for format/settings/photo/script controls.
- Done: keep full camera preview height while wiring compose/settings transitions.
- Pending: production behavior inside wired routes (real format application, full settings controls, media ingest handling).

Acceptance criteria (In Progress)

- Header + bottom nav bar are present and do not overlap camera focus area.
- Layout matches latest approved screenshot spacing.
- Done: controls route to working handlers instead of debug prints.
- Pending: destination flows complete end-to-end production logic.

Tests (Pending)

- UI: header + nav container exist and remain visible across device sizes.
- UI: header/footer controls trigger expected route/action behavior.

Phase 2 Wiring Sprint (Completed May 30, 2026)

- Done: wired `photo.on.rectangle` action to native media picker flow entry.
- Done: wired `sparkle.text.clipboard` action to compose/editor sheet.
- Done: wired `sun.max` action to settings route sheet.
- Done: replaced format panel print stub with real sheet toggle + placeholder controls.
- Done: added navigation/state model for camera vs compose mode transitions.
- Done: restricted media picker to video selection only (`.videos`) to match capture workflow.

## Phase 3 — Compose + Script Overlay Mode (In Progress)

Milestone: Script editing mode + scroll mode toggle from nav bar.

Checklist (In Progress)

- Done: Add "Compose" button in nav bar.
- Done: Compose opens directly to script editor sheet.
- Done: script editor auto-focuses and presents keyboard immediately on open.
- In Progress: Compose toggles between editing and scroll mode.
- Pending: Editor supports paste/type live updates.
- Pending: Keyboard dismiss via swipe + checkmark button.

Acceptance criteria (In Progress)

- Done: Text Input now enters keyboard-ready compose immediately (no extra tap inside sheet).
- Pending: Toggle switches reliably between edit and scroll.
- Pending: Script text updates reflect live in overlay.

Tests

- UI: compose toggle, keyboard dismissal, live update behavior.
- Unit: overlay mode state transitions.

## Phase 4 — Scroll Controls Panel (tab on bottom right)

Milestone: Slide-out panel with speed/font/color/bg opacity controls.

Checklist

- Add bottom-right tab toggle.
- Panel shows: Speed, Font Size, Text Color (white/black/red/blue/yellow), Text BG Opacity (0–15%).
- Panel sits above nav bar and does not block focus/exposure touch.

Acceptance criteria

- Panel opens/closes reliably.
- Changes reflect instantly in overlay.

Tests

- Unit: config clamping, color enum mapping, opacity bounds.
- UI: panel open/close, slider interactions.

## Phase 5 — Script Overlay Positioning + Safe Marker (In Progress)

Milestone: Default text position + optional safe marker.

Checklist

- Done: Default text starts above shutter and ends below top-left format panel.
- Done (Superseded): Right-lane thumb-width slider removed — replaced by direct viewport drag + center-reset button.
- Done: Compose save resets position to centered and re-measures against the new script's actual height.
- Done: Auto-scroll floor stops at "last line visible at top" instead of disappearing past the top.
- Done: Manual drag ceiling (`viewportH − lineH`) prevents dragging first line below viewport.
- Done: Simplified `TeleprompterGeometry` — removed `manualEndOffset`, `offset(forProgress:)`, `progress(forOffset:)`, `centerProgress`, `manualTravel`. Added `scrollStopOffset` + `dragCeiling`.
- Done: Removed `startOffsetProgress` from `TeleprompterConfig`.
- Done: Replaced `updateScriptStartProgress` / `resetScriptStart` in ViewModel with `teleprompterResetToken` + `resetTeleprompterPosition()`.
- Done: Completely refactored `TeleprompterOverlayView` — unified Pipeline A offset model (`baseOffset + manualOffset + drag + autoOffset`, clamped to `[scrollStopOffset, dragCeiling]`). Removed all dead code (`pausedOffset`, `scrollStartOffset`, `currentOffset(at:)`, `offsetForProgress`, `autoScrollFloor`, hidden measuring Text, preference key path).
- Done: Fixed hidden measuring Text layout bug — `fixedSize(vertical: true)` inflated the ZStack to full text height (6978pt for large scripts), causing `.frame(height: 500)` to center the oversized content ~3000pt off-screen. Removed hidden text; UIKit `remeasureText()` handles measurement.
- Done: Fixed `ScrollingTeleprompterText` rendering — replaced `fixedSize + offset + frame(maxHeight: .infinity)` chain with `GeometryReader + offset + frame(alignment: .topLeading) + clipped()` for reliable text positioning.
- Done: Removed `TeleprompterSwipeCaptureLayer`, `TeleprompterStartOffsetLane`, `kManualLaneEnabled` gate, and all related CameraView wiring.
- Done: Added diagnostic logging (`MEASURE`, `RESET`, `DRAG`, `isScrolling`) for runtime debugging.
- Pending: Add safe marker toggle (0–15%).

Acceptance criteria

- Done: Default position centers first line in viewport for both short and long scripts.
- Done: User can manually drag script up/down within bounds (`scrollStopOffset` to `dragCeiling`).
- Done: Center-reset button returns first line to viewport center.
- Done: Auto-scroll works correctly and bakes position on pause.
- Verified: Build passes with zero errors. Manual testing confirmed on device.

Tests

- Done: `TeleprompterConfig` clamping + default values (XCTest).
- Superseded: `offsetForProgress` tests no longer applicable (progress pipeline removed).
- Pending: Unit test for `TeleprompterGeometry.scrollStopOffset` and `dragCeiling` at various text/viewport sizes.
- Pending: UI test — drag to scroll, reset button returns to center.

Architecture reference (current Pipeline A)

- `totalY = clamp(startOffset + manualOffset + dragTranslationY + autoOffset, scrollStopOffset, dragCeiling)`
- `startOffset` = `viewportH/2 − padding − lineH/2` (first line centered)
- `scrollStopOffset` = `−(textH + padding)` (last line exits top)
- `dragCeiling` = `viewportH − lineH` (first line can't go below viewport)

## Phase 6 — Profile / Settings View (Completed)

Milestone: Settings view accessible from nav bar with live permission statuses.

Checklist (Done)

- Done: Show app name, version.
- Done: Live permission status display for Camera, Microphone, and Photo Library with colored indicators (green/orange/red).
- Done: Settings button in footer links to settings sheet.
- Done: Denied permissions show tappable "Settings" link to open iOS Settings.
- Done: Statuses auto-refresh on sheet appear and when returning from iOS Settings (`scenePhase`).

Acceptance criteria (Met)

- Settings view accessible from nav bar and displays real-time authorization status values.
- Each permission row shows SF Symbol icon, title, colored status dot, and status label.
- Denied permissions provide direct link to iOS Settings.

Tests

- Done: Manual — settings sheet opens, shows correct statuses, Settings link works.
- Pending: Unit — permission status mapper.
- Pending: UI — settings view loads from nav bar.

Phase 6 Implementation Notes (June 1, 2026)

- `CameraSettingsSheet` replaced static placeholder rows with `PermissionStatusRow` components.
- Added `AVFoundation` import to `CameraView.swift` for `AVCaptureDevice.authorizationStatus`.
- Status helpers (`avLabel`, `avColor`, `phLabel`, `phColor`) are private to the settings sheet.

## Phase 6A — Permissions Onboarding + App Assets (Completed)

Milestone: Unified permissions page gates camera entry; app icon and splash screen configured.

Checklist (Done)

- Done: Created `PermissionsOnboardingView.swift` — light-themed full-screen onboarding with three permission rows (Camera, Microphone, Photo Library).
- Done: "Grant Permissions" button serially requests all not-determined permissions.
- Done: "Continue" button enabled once Camera + Mic are granted (photo library recommended but not required).
- Done: Denied rows show tappable "Settings" link to open iOS Settings.
- Done: `scenePhase` listener refreshes statuses when returning from Settings.
- Done: `PromptCamApp.swift` gates root view with `@AppStorage("hasCompletedOnboarding")` — show-once behavior.
- Done: `PermissionService.swift` expanded with individual status getters, individual request methods, `allPermissionsGranted`, `cameraAndMicGranted`.
- Done: Photo library scope changed from `.addOnly` to `.readWrite` for video browsing/review.
- Done: `CameraViewModel.onAppear()` no longer requests permissions (assumes onboarding handled it).
- Done: `CameraView.swift` removed "Permissions Required" alert.
- Done: `CameraService.saveRecordingToPhotoLibrary()` guards on current status instead of re-requesting.
- Done: `NSPhotoLibraryAddUsageDescription` → `NSPhotoLibraryUsageDescription` in project.yml + pbxproj.
- Done: Created `Assets.xcassets` with `AppIcon` (1024×1024), `SplashIcon` (1x/2x/3x), and `AccentColor`.
- Done: Registered `Assets.xcassets` in pbxproj with `PBXResourcesBuildPhase`.
- Done: Created `PromptCam/Info.plist` with `UILaunchScreen` → `UIImageName: SplashIcon` for splash screen.
- Done: App icon visible on Home Screen, splash screen shows PromptCam icon on white background.

Acceptance criteria (Met)

- Fresh install shows onboarding page with all three permissions as "Not Set".
- Granting Camera + Mic enables Continue; tapping Continue transitions to camera.
- Subsequent launches skip onboarding and go directly to camera.
- App icon appears on Home Screen.
- Splash screen shows PromptCam icon centered on white background during launch.
- Recordings save without additional permission prompts.

Tests

- Done: Manual — clean install, permission grant flow, deny + Settings link, subsequent launch bypass.
- Done: Build verification — `xcodebuild clean build` passes with zero errors.
- Pending: Unit — `PermissionService.allPermissionsGranted` for all status combinations.

Files Changed (Phase 6A)

- New: `PromptCam/Views/PermissionsOnboardingView.swift`
- New: `PromptCam/Assets.xcassets/` (AppIcon, SplashIcon, AccentColor)
- New: `PromptCam/Info.plist`
- Modified: `PromptCam/Services/PermissionService.swift`
- Modified: `PromptCam/App/PromptCamApp.swift`
- Modified: `PromptCam/ViewModels/CameraViewModel.swift`
- Modified: `PromptCam/Views/CameraView.swift`
- Modified: `PromptCam/Services/CameraService.swift`
- Modified: `project.yml`, `PromptCam.xcodeproj/project.pbxproj`

## Phase 7 — Polish + Regression

Milestone: Final UI alignment and test stability.

Checklist

- Refine spacing, icon sizes, tap targets.
- Verify all controls visible with notch + safe areas.
- Add regression UI tests for main flow.

Acceptance criteria

- No overlaps, no clipped controls, tests stable.
