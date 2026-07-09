# PromptCam Phase 8 Rollout Checklist

Last updated: July 9, 2026
Owner: iOS + Product + Support
Status: Started (planning)

## Gate Status Snapshot

Date: July 9, 2026

1. Gate 1 (Phase 6 device QA complete with evidence): Blocked
Reason: `docs/PHASE6_QA_MATRIX.md` scenarios P6-01 through P6-15 are still marked Not Run.

2. Gate 2 (Phase 7 required analytics implemented and verified): Blocked
Reason: Remaining checklist items in Phase 7 are still open (settings-return delta, recovery success, blocked loop, support diagnostics, speech optional events).

3. Gate 3 (Full unit test suite green on release candidate build): Ready
Evidence: `xcodebuild -project PromptCam.xcodeproj -scheme PromptCam -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PromptCamTests test` completed with 129 tests, 0 failures.

4. Gate 4 (Critical permission-recovery bugs at severity high are zero): Blocked
Reason: No explicit zero-critical defect sign-off is documented in rollout artifacts yet.

Overall rollout gate result: Blocked (1/4 gates ready).

## Rollout Gates

1. Phase 6 device QA scenarios complete with evidence in `docs/PHASE6_QA_MATRIX.md`.
2. Phase 7 required analytics events implemented and verified.
3. Full unit test suite green on release candidate build.
4. Critical permission-recovery bugs at severity high are zero.

## Internal Beta

1. Build release-candidate branch for internal distribution.
2. Run targeted denial/recovery smoke scenarios (camera, mic, photos).
3. Validate Open Settings recovery from gate, runtime alert, and settings rows.
4. Collect internal feedback from at least 3 users.
5. Log defects and classify severity.

## TestFlight Phased Rollout

1. Wave 1: 10 percent audience for 24 hours.
2. Wave 2: 50 percent audience for 48 hours if no blocker issues.
3. Wave 3: 100 percent rollout after KPI and crash checks pass.
4. Pause rollout immediately if recovery failure rate regresses.

## Monitoring KPIs

1. Blocked-to-recovered conversion rate.
2. Open Settings tap-through rate from blocked states.
3. Save failure rate with photo-library permission context.
4. Speech-to-Text opt-in rate and denied/restricted distribution.
5. Repeated blocked-loop count.

## Rollback Criteria

1. Required permission recovery path fails on production build.
2. Crash spike linked to permission or onboarding flows.
3. Material drop in successful recording/save after update.

## Post-Rollout Review

1. Publish rollout summary with KPI trends and defect outcomes.
2. Document copy/CTA changes needed for next patch.
3. Create follow-up tickets for remaining analytics enhancements.
