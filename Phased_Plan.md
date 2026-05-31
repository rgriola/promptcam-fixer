May 31, 2026 - 1:00am - GitHub Copilot (Claude Opus 4.7)

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
- Done: Right-lane thumb-width slider for manual start-position adjustment.
- Done: Slider progress drives full off-screen-to-off-screen traversal (knob top → first line at viewport bottom; knob bottom → last line at viewport top). Scales linearly with text height — works for 100pt or 10,000pt scripts.
- Done: Compose save resets to knob-top (progress 1.0) and re-measures against the new script's actual height.
- Done: Auto-scroll floor stops at "last line visible at top" instead of disappearing past the top.
- Done: Simplified `TeleprompterOverlayView` + `TeleprompterConfig` (mutate-a-copy clamping, removed init-helper, optional `pausedOffset`, fallback plumbing, wrapper `ZStack`).
- In Progress: Manual slider knob behavior — knob/touch tracking still not aligning to script position as expected. Investigation pending.
- Pending: Add safe marker toggle (0–15%).

Acceptance criteria

- Done: Default position matches Q2.
- Done: User can adjust and retain position via the slider lane.
- In Progress: Manual slider drag reliably positions the script and matches knob location.

Tests

- Done: `TeleprompterConfig` clamping + default values (XCTest).
- Pending: Unit test for `offsetForProgress` linear mapping at progress 0, 0.5, 1.
- Pending: UI test — drag knob to position and verify script offset persists.

Math reference (current `offsetForProgress`)

- progress = 1 (knob TOP) → offset = `viewportHeight - 16` (script fully below)
- progress = 0 (knob BOTTOM) → offset = `-(textHeight - 16)` (script fully above)
- Linear interpolation between the two endpoints; total traversal = `viewportHeight + textHeight - 32`.

## Phase 6 — Profile / Settings View

Milestone: Settings view accessible from nav bar.

Checklist

- Show app name, version.
- Permission status display for Camera/Mic/Photo write.
- Settings button placeholder now links to view.

Acceptance criteria

- Settings view accessible and displays real status values.

Tests

- Unit: permission status mapper.
- UI: settings view loads from nav bar.

## Phase 7 — Polish + Regression

Milestone: Final UI alignment and test stability.

Checklist

- Refine spacing, icon sizes, tap targets.
- Verify all controls visible with notch + safe areas.
- Add regression UI tests for main flow.

Acceptance criteria

- No overlaps, no clipped controls, tests stable.
