# PromptCam Phase 6 QA Matrix

Last updated: July 9, 2026
Owner: iOS QA + Product
Scope: Permission denial/recovery validation for required and optional permissions

## Automated Preflight (Completed)

Date: July 9, 2026

1. Command: `xcodegen generate`
2. Command: `xcodebuild -project PromptCam.xcodeproj -scheme PromptCam -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PromptCamTests/AppEntryRouterTests -only-testing:PromptCamTests/PermissionPolicySnapshotTests -only-testing:PromptCamTests/RequiredAccessGateStateTests -only-testing:PromptCamTests/PermissionRecoveryMapperTests -only-testing:PromptCamTests/PermissionCopyCatalogTests test`
3. Result: 27 tests executed, 0 failures.
4. Coverage intent:
	- App-entry lifecycle routing decisions
	- Required/optional permission policy behavior
	- Required-access gate reducer behavior
	- Runtime error-to-recovery mapping behavior
	- Permission copy consistency behavior

Note: Device-level permission prompts, Settings round-trips, and restricted-state scenarios still require manual execution of P6-01 through P6-15.

## Environment

1. Device: iPhone (physical device preferred for permission prompts)
2. OS: iOS 18+
3. Build: feature/permission-ux-redesign (latest)
4. Install mode: fresh install for first-pass scenarios

## Global Pass Criteria

1. Required permission denial always routes to required-access gate.
2. Required blocked states always offer Open Settings recovery.
3. Returning from Settings updates gate and settings statuses without app reinstall.
4. Speech-to-Text denial never blocks camera entry when required permissions are granted.

## Test Matrix

| ID | Scenario | Setup | Steps | Expected Result | Status | Evidence |
|---|---|---|---|---|---|---|
| P6-01 | Fresh install allow all | Delete app, reinstall | Accept Camera, Mic, Photos | Camera screen opens; record+save enabled | Not Run |  |
| P6-02 | Fresh install deny Camera | Delete app, reinstall | Deny Camera; allow others | Required-access gate shown; Camera row blocked; Continue disabled | Not Run |  |
| P6-03 | Fresh install deny Microphone | Delete app, reinstall | Deny Microphone; allow others | Required-access gate shown; Microphone row blocked; Continue disabled | Not Run |  |
| P6-04 | Fresh install deny Photos | Delete app, reinstall | Deny Photo Library; allow others | Required-access gate shown; Photo row blocked; Continue disabled | Not Run |  |
| P6-05 | Revoke Camera after success path | Start from all granted | In iOS Settings deny Camera; reopen app | App routes to required-access gate on foreground/launch | Not Run |  |
| P6-06 | Revoke Microphone after success path | Start from all granted | In iOS Settings deny Mic; reopen app | App routes to required-access gate on foreground/launch | Not Run |  |
| P6-07 | Revoke Photos after success path | Start from all granted | In iOS Settings deny Photos; reopen app | App routes to required-access gate on foreground/launch | Not Run |  |
| P6-08 | Recover Camera denial | Camera denied state | Tap Open Settings; enable Camera; return | Gate refreshes; Camera no longer blocked; Continue state updates | Not Run |  |
| P6-09 | Recover Microphone denial | Microphone denied state | Tap Open Settings; enable Mic; return | Gate refreshes; Microphone no longer blocked; Continue state updates | Not Run |  |
| P6-10 | Recover Photos denial | Photos denied state | Tap Open Settings; enable Photos; return | Gate refreshes; Photo no longer blocked; Continue state updates | Not Run |  |
| P6-11 | Photo Library Limited | Fresh install or Settings | Choose Limited Photos access | Treated as granted for core flow; Continue enabled if Camera+Mic granted | Not Run |  |
| P6-12 | Speech denied with required granted | Required permissions granted | Deny Speech in Settings and return | Camera entry unaffected; Speech shows non-blocking optional messaging in Settings | Not Run |  |
| P6-13 | Restricted required permission | Screen Time/MDM restrictions | Restrict Camera or Mic or Photos | Required-access gate persists; Open Settings guidance shown | Not Run |  |
| P6-14 | Foreground refresh from unchanged Settings | Required permission denied | Open Settings then return without change | No navigation loop; state remains stable on gate | Not Run |  |
| P6-15 | Runtime copy/CTA consistency | Mixed denied/restricted states | Trigger blocked runtime and settings surfaces | Copy is consistent and action-oriented; Open Settings shown for required blocked states | Not Run |  |

## Execution Checklist

1. Run P6-01 through P6-15 in order.
2. Capture screenshots for each blocked state and each successful recovery.
3. Log any mismatch between gate status row and settings status row.
4. Record whether app required reinstall for recovery (must be No).

## Defect Template

1. ID: P6-XX
2. Build/Commit:
3. Device/OS:
4. Steps to Reproduce:
5. Expected:
6. Actual:
7. Severity:
8. Evidence (screenshot/video):

## Go/No-Go

1. Go when all required-permission denial/recovery scenarios pass with no dead-end flows.
2. No-Go when any required permission failure cannot be recovered via Open Settings + return.