# PromptCam Permission Recovery UX Plan (Draft)

Last updated: July 9, 2026
Owner: Product + iOS
Status: In Progress (Branch Draft)

## Goal

Ensure creators can always recover from denied Camera, Microphone, or Photo Library permissions without deleting and reinstalling the app.

Speech-to-Text permission is tracked and recoverable, but optional for core app use.

## Problem Summary

The app currently has recoverability paths, but they are fragmented and not always discoverable. Product intent says Camera, Microphone, and Photo Library are required for intended use, yet onboarding behavior and runtime error handling are not fully aligned to that rule.

## Product Rules (Proposed)

1. Required permissions: Camera, Microphone, Photo Library.
2. Optional permissions: Location, Speech-to-Text.
3. If any required permission is missing, user should see a dedicated Required Access gate.
4. Every blocked state must include a direct Open Settings recovery action.
5. Copy and behavior must match exactly across onboarding, runtime messaging, and settings.

## Permission Decision Table

| Camera | Microphone | Photo Library | Speech-to-Text | App Entry | Primary CTA | Continue Enabled | Record Enabled | Save Enabled |
|---|---|---|---|---|---|---|---|---|
| Granted | Granted | Granted or Limited | Any | Enter Camera | Continue | Yes | Yes | Yes |
| Denied or Restricted | Any | Any | Any | Required Access Gate | Open Settings | No | No | No |
| Any | Denied or Restricted | Any | Any | Required Access Gate | Open Settings | No | No | No |
| Any | Any | Denied or Restricted | Any | Required Access Gate | Open Settings | No | No | No |
| Not Determined present | Any | Any | Any | Required Access Gate | Grant Access | No (until all required granted) | No | No |

## UX Strategy

1. Replace first-launch-only onboarding with a persistent Required Access gate.
2. Show gate on first launch and any later launch where a required permission is revoked.
3. Keep in-camera Settings as a secondary recovery hub.
4. Convert permission-related runtime errors into action-oriented recovery prompts.
5. Refresh permission status automatically when returning from iOS Settings.
6. Show Speech-to-Text status in Settings as optional and non-blocking.

## Current Branch Progress Snapshot

Implemented:
1. Speech-to-Text added as optional permission in this plan.
2. Settings now includes a Speech-to-Text permission status row.
3. Shared permission status helpers include Speech status mapping.
4. Unit tests added for permission status mapping, including Speech-to-Text.

Pending:
1. Required Access gate redesign and routing updates.
2. Runtime blocked-state recovery prompts with Open Settings primary CTA.
3. Full QA matrix execution and phased rollout activities.

## Phased Plan With Checklists

## Phase 1: Product Alignment

Objective: Freeze policy and edge-case behavior before implementation.

Checklist:
- [x] Confirm required permission set (Camera, Microphone, Photo Library).
- [x] Confirm optional permissions (Location, Speech-to-Text).
- [x] Confirm whether Photo Library Limited is accepted.
- [x] Confirm whether Speech-to-Text denial should affect only transcription surfaces.
- [ ] Define behavior for Not now on required gate (exit, restricted shell, or other).
- [ ] Approve final policy matrix with founder/product.
- [x] Add unit tests for permission policy helpers and required-vs-optional gating decisions.

Deliverable:
- Approved permissions policy one-pager.

Phase 1 implementation notes:
1. `PermissionPolicySnapshot` now defines required-vs-optional permission policy in code.
2. Required = Camera + Microphone + Photo Library (`authorized` or `limited`).
3. Optional = Location + Speech-to-Text; optional denial does not block app entry.
4. Unit tests added for policy decisions and app-entry gating behavior.

## Phase 2: Copy and Messaging System

Objective: Make messaging clear, consistent, and action-oriented.

Checklist:
- [x] Replace ambiguous permission copy with impact-based text.
- [x] Standardize status labels (Granted, Not Set, Denied, Restricted).
- [x] Add a consistent recovery instruction pattern: Open Settings, enable access, return.
- [x] Write dedicated blocked-state copy for each required permission.
- [x] Add optional-state copy for Speech-to-Text (feature unavailable, app still usable).
- [x] Review copy for tone and accessibility.
- [x] Add unit tests for copy-key/state mapping utilities if implemented.

Deliverable:
- Approved copy deck for all permission states and screens.

Phase 2 implementation notes:
1. Onboarding copy now explicitly labels Camera, Microphone, and Photo Library as required.
2. Onboarding copy now labels Location and Speech-to-Text as optional.
3. Recovery guidance now explicitly tells users to use the row-level Settings actions when required access is blocked.
4. Copy is centralized in `PermissionCopyCatalog` to keep messaging consistent across onboarding surfaces.
5. `PermissionCopyCatalogTests` verifies required-vs-optional copy mapping and summary text presence.

## Phase 3: Required Access Gate UX

Objective: Implement a single blocking gate for missing required permissions.

Checklist:
- [x] Design gate layout with per-permission status rows.
- [x] Add per-row Open Settings action.
- [x] Add Grant Access action for Not Determined states.
- [x] Gate Continue until all required permissions are granted.
- [x] Ensure status refresh on app foreground return.
- [x] Add clear explanation of why each permission is required.
- [x] Add Speech-to-Text as optional status row (never blocks Continue).
- [x] Add unit tests for Required Access gate state reducer/view model logic.

Deliverable:
- Annotated wireframes and interaction spec.

Phase 3 implementation notes:
1. Onboarding gate now uses a centralized `RequiredAccessGateState` reducer.
2. Continue is now gated by all required permissions (Camera + Microphone + Photo Library).
3. Speech-to-Text is shown on onboarding as optional and does not block Continue.
4. App entry now routes back to the gate when required permissions are missing after prior onboarding.
5. Unit tests added for gate reducer behavior (`RequiredAccessGateStateTests`).

## Phase 4: Runtime Recovery UX

Objective: Remove dead-end errors and provide immediate recovery actions.

Checklist:
- [x] Map each permission-related technical error to a user-friendly recovery message.
- [x] Add Open Settings as a primary action in blocked runtime states.
- [x] Ensure photo save failures provide an immediate recovery route.
- [x] Prevent generic error-only dead ends for known permission failures.
- [x] Document fallback behavior for restricted permissions.
- [x] Add optional recovery messaging for Speech-to-Text-only denial.
- [x] Add unit tests for error-to-recovery mapping logic.

Deliverable:
- Error-to-recovery mapping table.

Phase 4 implementation notes:
1. Added `PermissionRecoveryMapper` to convert `CameraError` + live permission snapshot into a recovery message and primary action.
2. Runtime camera alert now promotes `Open Settings` when required permission states are blocked (denied/restricted).
3. Photo save failures with permission-like details now route users directly to Settings recovery.
4. Added restricted fallback guidance by reusing required-permission recovery copy for denied and restricted states.
5. Added optional Speech-to-Text recovery messaging in settings when speech permission is denied/restricted.
6. Added mapper unit tests in `PermissionRecoveryMapperTests`.

## Phase 5: Navigation and Lifecycle Integration

Objective: Ensure app routing always reflects current permission reality.

Checklist:
- [x] Re-check required permissions on launch.
- [x] Re-check required permissions on foreground resume.
- [x] Route to Required Access gate whenever required access is missing.
- [x] Keep in-camera Settings route available as backup recovery.
- [x] Verify no navigation loops when returning from Settings unchanged.
- [x] Keep Speech-to-Text status visible in Settings without blocking navigation.
- [x] Add unit tests for launch-routing decisions.

Deliverable:
- Navigation state diagram with transitions.

Phase 5 implementation notes:
1. Added `AppEntryRouter` as the centralized route decision for camera vs required-access gate.
2. `PromptCamApp` now re-checks required permission state on launch (`onAppear`) and on foreground resume (`scenePhase == .active`).
3. App entry now immediately routes to the required-access gate if any required permission is revoked after onboarding.
4. In-camera settings remains available as secondary recovery from camera surfaces.
5. Added route stability coverage for unchanged Settings returns to avoid navigation loop regressions.
6. Added launch-routing unit tests in `AppEntryRouterTests`.

## Phase 6: QA Matrix and Acceptance

Objective: Validate all denial and recovery paths before rollout.

Checklist:
- [ ] Fresh install: allow all permissions.
- [ ] Fresh install: deny Camera.
- [ ] Fresh install: deny Microphone.
- [ ] Fresh install: deny Photo Library.
- [ ] Allow all, then revoke one permission in iOS Settings.
- [ ] Recover from denied to granted for each required permission.
- [ ] Validate behavior for Photo Library Limited.
- [ ] Validate Speech-to-Text denied while all required permissions are granted.
- [ ] Validate restricted state (Screen Time or MDM).
- [ ] Validate background/foreground status refresh.
- [ ] Validate copy and CTA consistency across all states.
- [x] Add/update unit tests for implemented phase-level logic before sign-off.

Deliverable:
- Signed QA report and go/no-go recommendation.

Phase 6 implementation notes:
1. Added executable QA matrix with scenario IDs, setup, expected outcomes, and evidence fields in `docs/PHASE6_QA_MATRIX.md`.
2. Matrix includes all required checklist scenarios: fresh install denials, post-grant revocations, recovery flows, limited-photos handling, optional speech denial, restricted states, and foreground refresh stability.
3. Added go/no-go criteria and defect template to support sign-off.
4. Phase 6 status: In Progress (artifact complete; execution pending).

## Phase 7: Analytics and Supportability

Objective: Measure recovery success and detect dead-end friction.

Checklist:
- [ ] Instrument gate shown event.
- [ ] Instrument Grant Access and Open Settings taps.
- [ ] Instrument return-from-settings status delta.
- [ ] Instrument recovery success event (all required granted).
- [ ] Instrument repeated blocked loops.
- [ ] Add internal support diagnostic summary for current permission states.
- [ ] Add analytics events for optional Speech-to-Text enablement and denial.
- [ ] Add unit tests for analytics event payload builders.

Deliverable:
- Event taxonomy and dashboard definition.

## Phase 8: Rollout

Objective: Ship safely and monitor user outcomes.

Checklist:
- [ ] Internal beta for permission denial/recovery scenarios.
- [ ] TestFlight phased rollout.
- [ ] Monitor blocked-to-recovered conversion rate.
- [ ] Monitor save failures tied to Photo Library denial.
- [ ] Monitor Speech-to-Text opt-in and usage rates.
- [ ] Patch copy or CTA hierarchy if recovery rates are low.
- [ ] Run full unit test suite before each rollout increment.

Deliverable:
- Rollout report with follow-up action list.

## Acceptance Criteria

1. Users can recover denied required permissions without reinstalling.
2. Every blocked required-permission state has a direct Open Settings path.
3. App entry behavior always matches required-permission policy.
4. Runtime permission failures do not leave users at dead ends.
5. Permission statuses refresh correctly after returning from iOS Settings.
6. Speech-to-Text permission remains optional and never blocks core recording flow.

## Open Questions

1. Should Location remain optional or become required for this product version?
2. Is Photo Library Limited enough for all save and playback workflows?
3. Should users have a restricted read-only mode if they refuse required permissions?
4. What is the preferred tone for permission copy (strict, neutral, or coaching)?
5. Which speech permission status labels should be shown for denied and restricted?

## Suggested Next Step

Run a 30-minute review with Product, Design, and iOS to lock Phase 1 decisions, then convert this draft into an implementation ticket set.