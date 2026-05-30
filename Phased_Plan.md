May 29, 2026 - 11:20pm - GitHub Copilot

# PromptCam Phased Development Plan

Date: May 29, 2026 12:36pm

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

## Phase 1 — Camera Main View (In Progress)

Milestone: Selfie camera mimics iOS native camera controls using the iPhone17 reference.

Checklist (In Progress)

- Default to selfie camera (portrait).
- Add top-left record format panel (tappable to open settings stub).
- Keep only the native-like controls; remove the "XXXX" areas for future nav bar.
- Add touch AF/AE target indicator (visual only for now if needed).
- Add touch focus/exposure behavior with long-press lock and drag exposure adjustment.
- Ensure EV value is synced between header and focus indicator.

Acceptance criteria (In Progress)

- Selfie camera is default and persistent.
- Format panel visible and tappable.
- "XXXX" space stays empty/reserved.

Tests (Pending)

- UI: record button visible, format panel visible, selfie default.
- Unit: camera selection state default.

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
- Keep print("Specfic Message") instrumentation for button/panel wiring during Xcode validation.

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
- Done: bottom bar content reserved/cleared for Phase 2 nav-shell work.
- Done: test updates added for lock outcome matrix + camera UI smoke assertions.
- Remaining: manual on-device gesture feel pass and final header/footer spacing polish.

CameraView Subview Decomposition Map (Phased)

Phase 1 — Split Now

- CameraPreviewSurfaceView: preview rendering + tap/long-press gesture capture.
- FocusExposureOverlayView: reticle + EV slider visualization + drag callbacks.
- CameraTopControlsView: EV pill, format panel, and top status row.
- RecordingClusterView: shutter + script scroll control cluster.
- CameraLockStatusBadgeView: explicit AUTO / AE LOCK / AE-AF LOCK status text.

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

## Phase 2 — Nav Bar + Header Frame

Milestone: Camera UI framed with top header and bottom nav bar space.

Checklist

- Add top header container (left: format panel; right: settings placeholder).
- Add bottom nav bar container (reserved "XXXX" space).
- Maintain full camera preview height with safe-area aware layout.

Acceptance criteria

- Header + bottom nav bar present and do not overlap camera focus area.
- Layout matches screenshot spacing with reserved nav zones.

Tests

- UI: header + nav container exist and remain visible across device sizes.

## Phase 3 — Compose + Script Overlay Mode

Milestone: Script editing mode + scroll mode toggle from nav bar.

Checklist

- Add "Compose" button in nav bar.
- Compose toggles between editing and scroll mode.
- Editor supports paste/type live updates.
- Keyboard dismiss via swipe + checkmark button.

Acceptance criteria

- Toggle switches reliably between edit and scroll.
- Script text updates reflect live in overlay.

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

## Phase 5 — Script Overlay Positioning + Safe Marker

Milestone: Default text position + optional safe marker.

Checklist

- Default text starts above shutter and ends below top-left format panel.
- Add touch position adjust (default at 66% height, mid-right thumb-width lane).
- Add safe marker toggle (0–15%).

Acceptance criteria

- Default position matches Q2.
- User can adjust and retain position.

Tests

- Unit: position calculation utility.
- UI: drag to reposition and persist in session.

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
