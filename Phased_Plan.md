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
