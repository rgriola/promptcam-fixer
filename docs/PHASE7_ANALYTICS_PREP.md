# PromptCam Phase 7 Analytics Prep

Last updated: July 9, 2026
Owner: iOS + Product + Data
Status: Ready after Phase 6 sign-off

## Objective

Define a practical analytics contract for permission recovery so Phase 7 implementation is fast and consistent.

## Event Taxonomy

| Event Name | Trigger | Required Fields | Optional Fields |
|---|---|---|---|
| permission_gate_shown | Required-access gate appears | sessionId, userIdHash, blockedPermissions, appState | sourceScreen |
| permission_grant_access_tapped | User taps Grant Permissions on gate | sessionId, userIdHash, undeterminedPermissions | sourceScreen |
| permission_open_settings_tapped | User taps Open Settings from gate/runtime/settings | sessionId, userIdHash, permissionType, sourceSurface | blockedPermissions |
| permission_settings_returned | App becomes active after Settings | sessionId, userIdHash, changedPermissions, unchangedPermissions | timeInSettingsMs |
| permission_recovery_success | All required permissions become granted after blocked state | sessionId, userIdHash, recoveredPermissions, recoverySurface | recoveryDurationMs |
| permission_blocked_loop_detected | Gate shown repeatedly without required permission recovery | sessionId, userIdHash, loopCount, blockedPermissions | lastAction |
| speech_permission_status_observed | Speech status read on settings/onboarding refresh | sessionId, userIdHash, speechStatus | sourceScreen |
| speech_permission_open_settings_tapped | User taps Settings from Speech row/message | sessionId, userIdHash, sourceSurface | speechStatus |

## Field Contract

1. sessionId: app-launch scoped UUID
2. userIdHash: stable anonymized hash (no raw PII)
3. blockedPermissions: array of camera|microphone|photoLibrary
4. changedPermissions: map of permission -> previous/new status
5. sourceSurface: gate|runtimeAlert|settings
6. sourceScreen: onboarding|camera|settings
7. speechStatus: notDetermined|authorized|denied|restricted

## Dashboard KPIs

1. Gate show volume per app version
2. Open Settings tap-through rate from blocked states
3. Settings-return recovery rate (required permissions)
4. Median time-to-recovery after first blocked state
5. Repeated blocked loop rate
6. Speech permission opt-in rate among users with required permissions granted

## Implementation Sequence

1. Add analytics event enum/constants + payload builder types.
2. Instrument gate shown/tap actions and runtime Open Settings action.
3. Instrument foreground return permission diff event.
4. Instrument recovery success and blocked loop detection.
5. Instrument speech optional events.
6. Add payload builder unit tests.

## Unit Test Targets

1. Event name mapping is stable.
2. Required fields exist for each event type.
3. Permission status normalization maps iOS enums to analytics strings.
4. Diff builder correctly reports changed vs unchanged permissions.
5. No PII fields leak into payloads.

## Exit Criteria

1. All Phase 7 checklist items implemented.
2. Payload tests pass in CI.
3. Metrics are visible in analytics dashboard for internal beta.
