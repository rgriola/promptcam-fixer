# Audio Fix Plan: USB Recording Capture + Recording-Path VU Meter

## Goal

Make the VU meter and "No audio" warning reflect the **same audio that is actually
recorded**, fix the underlying device-binding bug so USB microphones actually
capture audio into the file, and make the "No audio" banner persist until audio
returns.

## Status (2026-08-29) — ✅ Core audio routing working

**Shipped and device-verified:** Phase 0, the Phase 1 cleanup, all of Phase 4, and
the two manual-test fixes from 2026-08-29 (findings 9 and 10).

**Device-verified working (2026-08-29):** live swapping between the DJI receiver,
Bluetooth, and the built-in mic via the Audio Sources panel. Routing follows the
user's pick, the VU meter tracks the active device, and the "No audio" banner
fires and clears correctly. This was the primary goal of the plan and it is met.

**Known remaining gap:** none outstanding from manual testing. Finding 11
(Bluetooth reconnect) is fixed and device-verified.

**Not started:** Phases 2, 3, 5 — the capture-output metering migration. Note that
the evidence that motivated them (mis-binding, contention) was refuted, so their
remaining justification is architectural rather than bug-driven. Re-litigate the
cost/benefit before starting (Open Question 6).

**Still open:** the silent recording has never been reproduced across five
instrumented runs. A candidate code path was found by inspection and hardened,
but remains unconfirmed.

**Test baseline:** 157 executed, 2 failures — the two known-failing
`PermissionStatusDisplayTests` cases, unrelated to audio.

## Background / Root Cause (verified in code at `974166e`)

The app currently has **two independent audio paths**:

|                  | VU meter                                                 | Recording                                                         |
| ---------------- | -------------------------------------------------------- | ----------------------------------------------------------------- |
| Engine           | `AVAudioEngine` tap on `inputNode` (`AudioMeterService`) | `AVCaptureSession` + `AVCaptureMovieFileOutput` (`CameraService`) |
| Device selection | Follows `AVAudioSession` preferred input (the USB mic)   | `AVCaptureDevice.default(for: .audio)`                            |
| USB workaround   | Yes — `installTap(..., format: nil)`                     | None                                                              |

Consequences:

- `configureSession()` binds the recording audio input with
  `AVCaptureDevice.default(for: .audio)`, which **ignores `setPreferredInput` and
  returns the built-in mic**. For USB mics reporting portType `'Other'`
  (e.g. DJI Wireless Rx), the movie file records the silent built-in mic while
  the meter shows the live USB signal.
- `reconfigureAudioInput()` (UID-matched, correct) is a **no-op during active
  recording**, so if the session started on the wrong device the whole clip is
  silent.
- The "No audio" banner is driven **only by the VU meter's silence watchdog**,
  so its state does not reflect the recorded audio.
- Toggling the transmitter off/on generates an `AVAudioSession` route change that
  forces `reconfigureAudioInput()` to rebind the capture input — which is why the
  problem mic "starts working" after a toggle.

### Competing hypothesis: single-stream USB contention (from `stash@{2}`)

A paused prior exploration (`stash@{2}`, "audio routing/USB recording exploration")
diagnosed a **different and more likely root cause**: USB / portType `'Other'`
mics expose a **single input stream**, so the `AVAudioEngine` metering tap and the
`AVCaptureSession` **cannot both read it**. The meter wins, and the recording
gets silence.

This explains every observed symptom at least as well as device mis-binding:

| Observation                  | Single-stream contention explanation                              |
| ---------------------------- | ----------------------------------------------------------------- |
| Meter live, recording silent | Engine tap holds the exclusive stream; capture session is starved |
| Second USB mic works         | Not single-stream / permits concurrent capture                    |
| Transmitter toggle fixes it  | Forces stream re-arbitration; capture session acquires it         |

The stash's workaround (`prepareForRecording()` / `endRecording()`) tore the
metering engine down for the duration of each recording. **That is rejected here**
— it makes the VU meter go dead exactly while recording, which directly violates
this plan's requirement that the meter track the recorded audio.

**This strengthens the case for Phase 2.** Moving metering onto
`AVCaptureAudioDataOutput` collapses two competing audio clients into one: the
capture session becomes the sole reader, contention disappears structurally, the
meter stays live during recording, and it reflects genuinely-recorded audio.

Both causes may be real and independent. Phase 1 fixes binding; Phase 2 fixes
contention. Neither alone is assumed sufficient.

**Harvest from the stash** (independent improvements, valuable regardless):

- Route-change reason inferred from whether the previous port still appears in
  `availableInputs`, instead of "current UID is nil" — correctly classifies
  external → built-in as a removal.
- `selectInput` returning `Bool` so a rejected `setPreferredInput` doesn't
  corrupt `lastSeenInputUID` or the displayed active-input name.
- `userPreferredInputUID` stickiness so poll-driven auto-recovery doesn't
  silently override an explicit user pick.

### Device findings — instrumented runs, iPhone 17 + DJI Wireless Mic Rx (2026-08-28)

Four untethered runs with the `[meter]` / `[startRecording]` / `[file]`
diagnostics. **Both original hypotheses are refuted on this hardware.**

**Binding is correct.** `FOLLOWS_ROUTE=YES`, `conn=enabled=true/active=true`,
`audioConnections=1`. iOS exposes exactly one audio `AVCaptureDevice`, a proxy
whose `uniqueID` is always `built-in_audio:0` and whose `localizedName` tracks
the route. See the invalidated Phase 1 below.

**No contention.** The engine tap ran for the whole of every take and the
recordings still contained audio. Meter and file agree closely:

| Take | meter peak during take | file peak  |
| ---- | ---------------------- | ---------- |
| 1    | —                      | −7.9 dBFS  |
| 2    | −18.5 dBFS             | −16.0 dBFS |

~2.5 dB apart. The tap and the capture session coexist fine on this device.

**The reproducible defect is the silence watchdog.** Three states measured:

| State             | ch1 rms          | ch1 peak         | actual signal    |
| ----------------- | ---------------- | ---------------- | ---------------- |
| Speech            | −27 … −45        | −16 … −35        | live             |
| Quiet room, TX on | −65 … −75        | −50 … −60        | live (room tone) |
| TX off            | −60.0 (sentinel) | −60.0 (sentinel) | **exactly 0.0**  |

Conclusions:

1. **The threshold is ~30 dB too high.** `silenceFloor = 0.005` is a _normalized_
   value; `normalizeDecibels` maps −60…0 dBFS onto 0…1, so the real trigger is
   **−59.7 dBFS RMS** — right through the middle of the quiet-room band. It
   false-fired twice on a working mic (t+30.4 s and t+52.3 s), once flapping
   fired→cleared inside ~1 s.
2. **Peak separates the states; RMS does not.** True silence peaks at exactly
   0.0; a quiet room peaks at −50…−60 dBFS. >50 dB of margin on the peak axis.
3. **The −60 sentinel is inverted.** `rms == 0` is logged/normalized as −60.0,
   which is _higher_ than genuine room tone (−74.4). Any dB-threshold comparison
   is therefore fighting a value that is larger in the worse case.
4. **The watchdog's true-positive path works.** TX off → digital zero → fired →
   banner shown, confirmed on device.
5. **Silent delivery ≠ stalled delivery.** With TX off, buffers kept arriving at
   normal cadence carrying zeroes. Phase 3 must treat "no buffers" and
   "zero-valued buffers" as distinct.
6. Watchdog reads **ch1 only**, so muting TX1 while TX2 stays live would also
   false-fire. (DJI maps TX1→ch1, TX2→ch2; an unpaired slot is digital zero.)
   **Confirmed on device:** transmitting on TX2 only, ch1 held the −60.0 sentinel
   for a full 50 s run while ch2 tracked speech from −65 to −26 dBFS. Reading ch1
   alone, the watchdog would fire 5 s after launch on every connection — so the
   max-across-channels fix is load-bearing, not defensive.
7. `onChange(of: Float) action tried to update multiple times per frame` — the
   level publisher outruns SwiftUI's frame rate. Noted, not addressed here.
8. **Unplug was misclassified as an arrival.** `pollRouteForChange` inferred the
   route-change reason from `currentUID != nil`, but removing USB audio falls
   straight back to the built-in mic, so the UID is never nil. The unplug took
   the `.newDeviceAvailable` path, found no external candidate, and fell through
   to `evaluateCurrentRoute()` — which publishes the route but never restarts the
   engine. The tap stayed bound to the removed device and the meter went dead,
   while recording (a separate path) kept working. Fixed by classifying on
   whether the route _landed_ on an external port, and by restarting the engine
   when the arrival path finds no external candidate.
9. **The persistent banner could latch forever (found by manual test,
   2026-08-29).** Repro: DJI TX off → banner appears → pull the DJI RX with
   AirPods still connected → meter and recording both move to AirPods, but the
   banner never clears. Cause: `startMetering()` reset `silenceAlertFired = false`
   **silently**, so the service forgot it had alerted and the recovery callback
   never fired, leaving `showAudioSilenceWarning` stuck `true`. Any route change
   restarts the engine, so this stranded the banner on every recovery-by-swap.
   The old 6 s auto-dismiss had been masking the desync; making the banner
   persistent exposed it. Fixed by firing the recovery callback when the reset
   clears a previously-fired alert — if the new route is also silent the watchdog
   simply re-fires after 5 s.
10. **The picker could not change audio source with two externals connected
    (found by manual test, 2026-08-29).** `.newDeviceAvailable` called
    `findExternalInput()`, which returns the **first** external in enumeration
    order. With AirPods and the DJI both connected, an explicit picker choice
    was immediately overridden by the poller re-selecting whichever enumerated
    first. Fixed with `userPreferredInputUID` stickiness: `selectInput()` records
    the user's pick, route handling prefers it while it remains available, and
    the pick is dropped once the device disappears so auto-fallback isn't
    blocked. Internal route handling now calls `applyPreferredInput()`, which
    does not overwrite the user's choice. (This is the "stickiness" item listed
    in the stash-harvest notes above.)
11. **A reconnecting Bluetooth device is invisible while another input holds the
    route (found by manual test, 2026-08-29). FIXED and device-verified.** Repro:
    swap to AirPods in the panel, disconnect them, then put them back in — the
    app did not pick them up. Two independent causes:
    - `pollRouteForChange()` returned early on
      `guard currentUID != lastSeenInputUID`, so it only ever reacted to the
      **current route input** changing. A device that becomes _available_ without
      iOS moving the route to it produces no UID change, so no callback fired,
      `onInputsAvailable` never re-published, and `availableAudioInputs` went
      stale. Reopening the panel worked around it because
      `openAudioSourcePicker()` re-reads `AVAudioSession.availableInputs`
      directly.
    - `.oldDeviceUnavailable` cleared `userPreferredInputUID` when the picked
      device disappeared, so the user's choice was not restored when that same
      device returned.

    Fixed by tracking `lastSeenAvailableUIDs` (the _set_ of available input
    UIDs) alongside the active-route UID. When the set changes the poller
    republishes via `evaluateCurrentRoute()`, and if a newly-arrived UID matches
    the user's standing pick it is re-selected. `.oldDeviceUnavailable` no longer
    clears the pick — `userPreferredAvailableInput()` already returns nil while
    the device is absent, so a retained pick cannot block fallback.

**Still unreproduced:** the silent recording. Five runs, zero occurrences. The
original report likely bundled two separate defects — a false "no audio" banner
(now explained and fixed) and a rarer silent-recording event that has not yet
been captured.

**Candidate mechanism for the silent recording (found by inspection, 2026-08-28).**
In `configureSession()`, `audioDevice` is assigned before the `canAddInput` check
that assigns `audioInput`. If `canAddInput` fails, `audioDevice` is set while no
input is attached. `reconfigureAudioInput()` then matched on device identity
alone, logged "audio device unchanged", and returned — so the session recorded
with no audio track permanently, with no retry and no error logged. This matches
the reported symptom exactly: meter live, file silent. Guard now also requires
`audioInput != nil`, and both failure paths log an error so the next occurrence
is visible. Unconfirmed as the cause — it has not been observed on device.

### Key files

- `PromptCam/Services/CameraService.swift` — `session`, `sessionQueue`,
  `movieFileOutput`, `audioInput`/`audioDevice`, `configureSession()`,
  `reconfigureAudioInput()`
- `PromptCam/Services/CameraService+Recording.swift` — `startRecording`
- `PromptCam/Services/AudioMeterService.swift` — `processBuffer`, silence/first-buffer
  watchdogs, route polling, callbacks
- `PromptCam/…/AudioMeterViewModel.swift` — `showAudioSilenceWarning`,
  `isExternalMic` gating, `selectAudioInput`
- `PromptCam/…/CameraView.swift` — `TemporaryWarningBanner` usage (~L214)
- `PromptCam/…/TemporaryWarningBanner.swift` — auto-dismiss `.task`

Note: `AVCaptureAudioDataOutput` / `AVCaptureVideoDataOutput` are not used anywhere
today. `AudioMirror.swift` does not exist.

## Decisions

- **Fix recording too** (device-binding + pre-record re-sync), not just the meter.
- **Metering source:** `AVCaptureAudioDataOutput` tapped off the recording session,
  added **as an additional, feature-gated source alongside the existing
  `AVAudioEngine` tap** — not a same-PR replacement. The engine tap is only
  removed once the capture-output source has demonstrably equivalent
  resilience (see Phase 5).
- **Device binding must fail loudly, not silently fall back.** If the active
  `AVAudioSession` route is external and no `AVCaptureDevice` can be UID-matched
  to it, that is treated as an unmappable/unsupported device — surfaced as an
  explicit error/warning — **not** silently resolved via
  `AVCaptureDevice.default(for: .audio)`. The default-device fallback is only
  valid when the active route is genuinely built-in or absent.
- Keep the `isExternalMic` gate on the silence warning (a quiet room on the
  built-in mic is not a fault; a silent USB mic still qualifies as external).
- Out of scope: switching to `AVAssetWriter`; unrelated concurrency refactors.

### Rubber-duck review (2026-08-28)

An independent review of this plan (pre-implementation) flagged that the
original phase order removed proven engine-tap recovery/watchdog logic
(Phase 2) before its capture-output replacement had equivalent resilience,
and added the meter (Phase 1) before fixing device binding (Phase 3) — which
would let a wrongly-bound meter and wrongly-bound MOV silently agree with each
other. Phases below are reordered to close both gaps: device binding is fixed
and hardware-verified first, capture-output metering is added as a
feature-gated addition (not a replacement) second, and engine retirement is a
final, separately-gated step contingent on proven resilience parity.

## Base Branch

- `main` = `d8d6ca2` (already contains `d5b919e` concurrency cleanup).
- `inspect-974166e` is a throwaway build branch for regression hunting.
- **The fix branches off `main`** so it builds on the current `AudioMeterService`.
  Confirm before starting.

## Phase 0 — Pre-work Gate ✅ COMPLETE (2026-08-28)

- [x] Confirm base branch = `main` (`d8d6ca2`, contains `d5b919e`). ✅
- [x] **Verify, don't assume, the `d5b919e` behavioral baseline.** ✅ — reviewed.
      **Verdict: NOT annotation-only. The commit message's "No behavior changes"
      claim is inaccurate.** Findings below.

### `d5b919e` blast radius

| File                                                   | Lines | Nature                                |
| ------------------------------------------------------ | ----- | ------------------------------------- |
| `PromptCam/Services/AudioMeterService.swift`           | 77    | **Substantive** — timer/idiom rewrite |
| `PromptCam/Services/CameraService.swift`               | 8     | `nonisolated` annotations             |
| `PromptCam/Services/CameraService+Recording.swift`     | 1     | Comment only                          |
| `PromptCam/Views/Recordings/RecordingPlayerView.swift` | 2     | Unrelated                             |

### What actually changed in `AudioMeterService`

Three scheduled timers were converted from `DispatchWorkItem` +
`DispatchQueue.main.asyncAfter` to
`Task { @MainActor … try? await Task.sleep … guard !Task.isCancelled … }`:

- `restartWorkItem` → `restartTask` (route-change restart debounce)
- `firstBufferWatchdogWorkItem` → `firstBufferWatchdogTask`
- `reconnectFallbackWorkItem` → `reconnectFallbackTask` (2.5 s fallback)

Plus interruption delivery changed from
`DispatchQueue.main.async { self?.handleInterruption(typeRaw:) }` to
`Task { @MainActor in self?.handleInterruption(typeRaw:) }`.

### Risks identified

- **(a) HIGH — interruption ordering guarantee lost.** `DispatchQueue.main.async`
  is FIFO; **unstructured `Task { @MainActor }` has no ordering guarantee**.
  `handleInterruption` is an order-sensitive state machine: `.began` sets
  `isInterrupted = true` and clears `pendingReconnectAfterInterruption`;
  `.ended` clears `isInterrupted`, sets pending, and arms the 2.5 s fallback.
  If a rapid `.began`→`.ended` pair is reordered to `.ended`→`.began` — exactly
  the "rapid Siri + dictation back-to-back" case the code comments call out —
  the service settles at `isInterrupted = true` with
  `pendingReconnectAfterInterruption = false`, i.e. **metering dead with no
  fallback to recover it**. That is the original "dictation freezes the
  camera / VU meter dead" symptom class this subsystem was hardened against.
- **(b) MEDIUM — cancellation is now cooperative, not preemptive.**
  `DispatchWorkItem.cancel()` before its deadline guaranteed the body never
  ran. `Task.cancel()` merely wakes `Task.sleep` early and execution continues
  to the `guard !Task.isCancelled`. The guards are present and correct at all
  three sites today, but this is now correctness-by-convention that a later
  edit (including Phases 3 and 5) can silently break by inserting work above
  the guard.
- **(c) LOW — timing precision and priority.** `Task.sleep` leeway differs from
  `asyncAfter`, and an unstructured `Task {}` inherits the caller's priority
  rather than running at main-queue priority. The tuned delays
  (0.3 s / 0.8 s / 1.2 s / 2.5 s) may drift under load.
- **(d) Pre-existing, not introduced — but do not worsen.**
  `firstBufferWatchdogTask` is mutated from `processBuffer` on the **real-time
  audio tap thread** and from `@MainActor` tasks, unsynchronized, on an
  `@unchecked Sendable` class. This was equally true of the old
  `DispatchWorkItem`.

### Test-coverage gap

`AudioMeterServiceInterruptionTests` calls `service.handleInterruption(typeRaw:)`
**directly and synchronously**, bypassing the notification-delivery path that
`d5b919e` actually changed. The commit's "test suite verified green" therefore
did **not** exercise the modified code path, and **no test covers `.began`/
`.ended` ordering**.

### Baseline test state on `main` (recorded 2026-08-28)

Simulator: iPhone 17 Pro (`8D6BE6A7-E123-4340-935B-C821EB89ACCB`).

- `PromptCamTests`: **155 executed, 2 failures** — the suite is _not_ green:
  - `PermissionStatusDisplayTests.testPhotoAuthorizationStatusColors` — `"yellow"` != `"green"`
  - `PermissionStatusDisplayTests.testPhotoAuthorizationStatusLabels` — `"Limited"` != `"Granted"`
  - Both concern photo-library authorization display mapping, are outside
    `d5b919e`'s blast radius (file last touched by `2468820`, "Permission
    Recovery UX Redesign"), and are unrelated to audio. **Treat as known-failing
    baseline, not as regressions from this work.**
- `AudioMeterServiceInterruptionTests` + `CameraServiceInterruptionTests`:
  **17 executed, 0 failures.** ✅

### Phase 0 exit actions — DECIDED: Option A

Risk (a) disposition: **restore FIFO delivery via `DispatchQueue.main.async`.**
Rejected the actor / `AsyncStream` alternative _for now_ — Phase 0's purpose is to
establish a _trustworthy_ baseline, and swapping in a brand-new transport would
make the reference implementation itself unproven immediately before Phases 1–5
perform major surgery on this file. A one-line revert restores a mechanism with
proven field behavior. Ordering is a correctness concern; GCD-vs-`Task` idiom
consistency is a style concern, and correctness wins.

**Scope the revert narrowly.** The three timer conversions (`restartTask`,
`firstBufferWatchdogTask`, `reconnectFallbackTask`) stay as-is — each is a single
self-cancelling scheduled action where ordering is irrelevant, and their
`guard !Task.isCancelled` checks are correct. Only the interruption observer
carries an ordered event stream.

- [x] Revert the interruption observer in `startMonitoringRoute()` to
      `DispatchQueue.main.async { self?.handleInterruption(typeRaw: typeRaw) }`,
      with a comment explaining why it is deliberately **not** a `Task` (so a
      future "unify the idiom" pass doesn't silently reintroduce the bug). ✅
- [x] Add **defense in depth**: capture a monotonically increasing sequence
      number synchronously inside the observer (before the hop) and have
      `handleInterruption` discard stale deliveries. This makes the state machine
      order-insensitive _regardless of transport_, so a later `AsyncStream`
      migration cannot resurrect risk (a). ✅ — `stampInterruptionSequence()` +
      private `handleInterruption(typeRaw:sequence:)`; the existing
      `handleInterruption(typeRaw:)` remains as a `sequence: nil` seam for tests.
- [x] Add a regression test that drives interruption **through the notification
      path** (not the direct `handleInterruption` call) and asserts rapid
      `.began`/`.ended` pairs settle correctly. ✅ —
      `test_notificationPath_beganThenEnded_settlesNotInterrupted` and
      `test_notificationPath_rapidBurst_preservesOrder`.
- [ ] Hardware regression matrix (route polling, interruption begin/end,
      fallback reconnect timing, first-buffer retry) still requires the DJI
      receiver — run on-device before relying on this baseline.

**Post-fix test state:** 157 executed, 2 failures — the same two known-failing
`PermissionStatusDisplayTests` cases as the baseline. No new regressions.
Interruption suites: 19/19 green.

## Phase 1 — ❌ PREMISE INVALIDATED by hardware run (2026-08-28)

**Hypothesis A (device mis-binding) is dead. Do not implement this phase as
written.**

An untethered iPhone 17 run with the DJI Wireless Mic Rx produced a clean,
working recording _and_ disproved the assumption Phase 1 was built on.

What the instrumented run showed:

```
[startRecording] route='Wireless Mic Rx' type=USBAudio
                 uid=AppleUSBAudioEngine:DJI…:Wireless Mic Rx:XSP12345678:1
                 | bound='Wireless Mic Rx'
                 uid=com.apple.avfoundation.avcapturedevice.built-in_audio:0
                 conn=enabled=true/active=true
[startRecording] candidate 'Wireless Mic Rx'
                 uniqueID=com.apple.avfoundation.avcapturedevice.built-in_audio:0
[record]         STARTED connections=2 audioConnections=1
[file]           audioTrack duration=10.73s bitrate=92766bps peak=-7.9 dBFS
```

Three conclusions:

1. **iOS exposes exactly one audio `AVCaptureDevice`.** The discovery session
   returned a single candidate. Its `uniqueID` is the fixed proxy
   `com.apple.avfoundation.avcapturedevice.built-in_audio:0`; only its
   `localizedName` tracks the route. It reported `Wireless Mic Rx`.
2. **`AVCaptureDevice.default(for: .audio)` does _not_ return the built-in mic
   when an external mic is routed.** The doc comment above
   `reconfigureAudioInput()` claiming otherwise is wrong, and the UID-matching
   code it justifies can never match — it always falls through to the default,
   which is the correct device anyway. That code is dead, not load-bearing.
3. **Recording captured real audio at −7.9 dBFS peak** while the engine tap was
   live for the whole take. So on this device the tap and the capture session
   _can_ coexist — this run did not reproduce contention either.

Revised action:

- [x] Delete the unreachable UID-matching branch in `reconfigureAudioInput()`
      and correct the misleading doc comment, so the next reader doesn't rebuild
      this same wrong theory. ✅ **DONE.** The discovery-session UID match was
      removed and the doc comment replaced with the verified proxy behaviour.
      Note: the _swap_ block below it was initially assessed as unreachable too,
      but that was wrong — it is the recovery path for a session configured
      without an audio input, and it was kept. See the candidate-mechanism note
      above.
- [x] Do **not** add a fail-loud "unmappable device" path — there is nothing to
      map. Route selection is owned entirely by
      `AVAudioSession.setPreferredInput`, which the logs show working. ✅
      Confirmed across four route transitions.

## Phase 1 (original, superseded) — Fix the Actual Recording Device Binding

_(Moved ahead of the metering-source work: fixing binding first lets Phase 2
prove the meter is watching genuinely-correct audio, instead of an
already-broken built-in-mic path.)_

- [ ] Extract a shared `resolveAudioCaptureDevice()` helper that UID-matches the
      active `AVAudioSession` route input to an `AVCaptureDevice`.
- [ ] **No silent built-in fallback.** If the active route is external
      (including USB portType `'Other'`, e.g. DJI Wireless Rx) and no capture
      device UID-matches it, treat this as an unmappable/unsupported device:
      log the active route UID and all candidate `uniqueID`s, surface an
      explicit error/warning, and block or flag the recording rather than
      silently resolving to `AVCaptureDevice.default(for: .audio)`. Reserve the
      default-device fallback for when the active route is genuinely built-in
      or there is no active route.
- [ ] Replace `AVCaptureDevice.default(for: .audio)` in `configureSession()` with
      the shared helper.
- [ ] Implement a **single atomic `sessionQueue`-owned preflight operation**
      (e.g. `prepareAndStartRecording`) that: resolves the current settled
      `AVAudioSession` route, compares it to the currently bound capture
      input, rebinds via `reconfigureAudioInput()` if needed (while not
      recording), verifies the movie output has a live audio connection, and
      only then calls `startRecording`. Do not rely on "call
      `reconfigureAudioInput()` immediately before `startRecording`" as a
      call-order convention — `reconfigureAudioInput()` and `startRecording()`
      are both independently `sessionQueue`-dispatched and async, so ordering
      at the call site does not guarantee sequencing or that
      `AVAudioSession.currentRoute` has settled after `setPreferredInput`.
- [ ] **Hardware-verify before proceeding**: confirm on the DJI receiver (and a
      second USB mic) that the resulting MOV actually contains the external
      mic's audio, independent of any meter change. This is the phase's exit
      criterion — do not start Phase 2 until this passes on real hardware.
- [ ] **Isolate binding from contention when verifying.** If the single-stream
      hypothesis is correct, this exit criterion may fail _even with binding
      fixed_, because the `AVAudioEngine` tap still holds the mic's only input
      stream. Run the verification twice: once normally, and once with metering
      stopped (`stopMetering()`) to remove contention. Record both results. - Silent in both runs → binding is still wrong; Phase 1 is incomplete. - Audio only with metering stopped → binding is fixed and **contention is
      confirmed** as the remaining cause; that is a legitimate Phase 1 pass,
      and Phase 2 is what actually closes the bug. - Audio in both runs → contention is not a factor for this device.

## Phase 2 — Recording-Path Metering Source (additive, feature-gated)

- [ ] Add an `AVCaptureAudioDataOutput` to `CameraService.session` in
      `configureSession()` alongside `movieFileOutput`, with a sample-buffer
      delegate on a dedicated serial audio queue. Add it **behind a feature
      flag / alongside the existing engine tap** — this is an additional
      source, not yet a replacement.
- [ ] Explicitly request and validate the delegate's audio format
      (`AVCaptureAudioDataOutput.audioSettings`); inspect the actual
      ASBD/`AudioBufferList` received rather than assuming Float32/planar
      layout. Support or safely reject non-float/interleaved layouts.
- [ ] Implement `AVCaptureAudioDataOutputSampleBufferDelegate` to read each
      `CMSampleBuffer`'s PCM, derive channel count from the format description
      (stereo detection), and forward per-channel float data to
      `AudioMeterService`. Keep delegate work bounded (level math only, no
      blocking I/O/UI work) and publish throttled values.
- [ ] Treat a data-output delivery stall as "meter unavailable," never as
      proof of silence in the recording — the delegate confirms buffers were
      delivered upstream, not that the movie output encoded/muxed them.

## Phase 3 — Capture-Session-Aware Meter Liveness

_(New phase, added because capture-output metering has no signal at all when_
_the session stalls — unlike the engine tap, it can't rely on "silence within a_
_live buffer stream" detection.)_

- [ ] Add a delivery-liveness timer independent of buffer arrival (i.e. it can
      fire even when zero buffers have arrived) to detect a stalled/stopped
      capture session, distinct from the existing silence watchdog (which
      detects quiet-but-flowing audio).
- [ ] Re-arm this liveness timer after every `session.startRunning()`,
      interruption begin/end, route input reconfiguration, and
      `mediaServicesWereReset` recovery.
- [ ] Explicitly wire `CameraService`'s running / interruption / runtime-error
      state into the meter's liveness state, so the meter can distinguish
      "no audio because true silence" from "no audio because the capture
      session isn't delivering buffers."
- [ ] Confirm `mediaServicesWereReset` recovery (`CameraService.swift`, which
      tears down and re-adds session inputs/outputs) explicitly re-adds the
      `AVCaptureAudioDataOutput` and reinstalls/validates its delegate queue,
      and that meter liveness state is invalidated and rearmed as part of that
      recovery — not just the video pipeline.

## Phase 4 — ✅ COMPLETE (2026-08-28) — Silence Detection + Persistent Banner

_(Promoted ahead of Phases 2–3: this is the one defect reproduced on device, and_
_it is independent of the metering-source work. Items 1–2 had to land before 3, or_
_a persistent banner would latch on every quiet pause.)_

- [x] **1. Drive the watchdog off peak with a −80 dBFS floor.** Twenty dB below
      the quietest measured room tone and far above digital zero. Preferred over
      testing `rms == 0` exactly, which would break on a receiver that emits
      dither or a small DC offset instead of hard zero. Implemented as
      `silencePeakFloor = 0.0001`; the old normalized `silenceFloor` was deleted.
- [x] **2. Take the max across channels**, so muting one transmitter while the
      other stays live does not false-fire. **This turned out to be essential,
      not defensive** — see finding 6.
- [x] **3. Make `TemporaryWarningBanner.autoDismissAfter` optional**; skip the
      auto-dismiss `.task` when `nil`. No-Audio banner now passes `nil` and
      clears only via the watchdog's recovery callback.
- [x] **4. Reword the message** to "No audio signal. Check that your microphone
      is on and in range."

Also fixed in this pass (finding 8): route-change reason inference in
`pollRouteForChange`, plus an engine restart when the arrival path finds no
external candidate. **Device-verified** across plug → unplug → plug → unplug:
correct `reason=2`/`reason=1` classification, clean re-bind within ~1.6 s each
time, and format tracking `2ch` ↔ `1ch`.

Still deferred: once Phase 3 lands, the banner must additionally distinguish
"true silence" from "meter unavailable" so it doesn't fire during a stalled or
recovering capture session.

**Known gap introduced by the persistent banner.** The silence warning is still
gated on `isExternalMic` (`AudioMeterViewModel`), so a genuinely dead built-in
mic produces no warning at all. That gate was reasonable when the banner
auto-dismissed after 6 s; it is a narrower fit now. Decide before shipping.

## Phase 5 — Retire the AVAudioEngine Level Source (gated on proven parity)

_(Last, not second — do not remove the engine tap until the capture-output_
_source has run the same stress/regression matrix the engine path was built to_
_survive.)_

- [ ] Run the full hardware and interruption/reset stress matrix (Verification
      section below) against the capture-output source with the engine tap
      still present as fallback. Only proceed once it demonstrably preserves
      the engine path's resilience (dictation interruption, route hot-swap,
      `mediaServicesWereReset`).
- [ ] Refactor `AudioMeterService.processBuffer` into a source-agnostic level
      function (RMS / peak / peak-hold / silence watchdog) fed by the capture
      buffers instead of the engine tap.
- [ ] Remove the engine tap, the first-buffer watchdog, and engine-restart logic
      tied to the tap.
- [ ] `AudioMeterService` retains: `AVAudioSession` category/route configuration,
      1 Hz route polling, input enumeration/selection for the picker,
      `setPreferredInput`, and the silence watchdog + callbacks
      (`onSilenceWatchdog`). Public callback surface stays stable for
      `AudioMeterViewModel`.
- [ ] **Revisit the deferred `AsyncStream` migration here (optional).** Phase 0
      chose `DispatchQueue.main.async` for interruption delivery to preserve FIFO
      ordering (see Phase 0, risk (a)). This phase already restructures the file,
      so it is the right moment to reconsider serializing interruption delivery
      via an actor or `AsyncStream` if idiom consistency is still wanted. Only do
      so with the Phase 0 sequence-number guard and the notification-path
      ordering test already in place and green — they are what make the swap
      provable rather than hopeful. Removing the engine tap also deletes the
      remaining `DispatchWorkItem`-era machinery, so the GCD/`Task` mix shrinks
      on its own; migrating is a preference, not a requirement.

## Verification

### Unit tests

- [ ] Test `resolveAudioCaptureDevice()` selection logic: built-in, USB UID
      match, and the **fail-loud unmappable-external-device path** (must not
      silently return the default device). Validate against the DJI receiver's
      actual identifiers, not just invented test doubles — a synthetic test
      cannot establish that iOS exposes a usable mapping for real hardware.
- [ ] Extract the level math (RMS / peak) into a source-agnostic function and test
      it against a synthetic buffer with known RMS/peak, including zero-frame,
      mono, and stereo/channel-silence cases.
- [ ] Test the capture-output PCM/format handling against the actual
      `AVCaptureAudioDataOutput.audioSettings` format, not assumed Float32/planar
      layout.
- [ ] Test meter liveness transitions (Phase 3): stalled/no-buffer state vs.
      true-silence state, independent of each other.
- [ ] Keep existing suites green: `CapturePolicyTests`, `PermissionCascadeTests`,
      `PermissionGatingTests`, `RotationCorrectionTests`.

### Manual device matrix (problem USB mic / second USB mic / built-in)

- [x] Recorded MOV actually contains USB audio (verify **before** any meter
      change lands, per Phase 1's exit criterion).
- [x] VU meter matches the recorded file's audio.
- [x] Persistent "No audio" banner appears on true silence and clears when audio
      returns. **Bug found and fixed (2026-08-29)** — see finding 9. Still
      outstanding: must not fire spuriously during a stalled/recovering capture
      session (Phase 3 liveness distinction).
- [ ] Dictation-interruption recovery still works with the capture-output
      meter active (Phase 3), not just with the original engine tap.
- [x] Route-change picker and hot-swap (while not recording) still work.
      **Bug found and fixed (2026-08-29)** — see finding 10. Re-verified
      2026-08-29: DJI ↔ Bluetooth ↔ built-in swapping via the Audio Sources
      panel routes correctly and the meter follows.
- [x] A Bluetooth input that reconnects while another device holds the route is
      picked up automatically — see finding 11. Verified 2026-08-29: disconnect
      AirPods mid-session, fallback occurs, reconnecting re-lists and re-selects
      them.
- [ ] `mediaServicesWereReset` recovery re-establishes both the audio data
      output and meter liveness (Phase 3).
- [ ] Only after all of the above pass with the engine tap still present as
      fallback: remove the engine tap (Phase 5) and re-run the full matrix
      once more to confirm parity.

## Open Questions

1. ~~`d5b919e` stability review is still blocked~~ — **DONE (2026-08-28).**
   Review performed; see Phase 0. Outcome: `d5b919e` is **not** behavior-neutral.
   The open decision is now risk (a): whether to restore FIFO interruption
   delivery before Phases 1–5 build on `AudioMeterService`.

2. Should the persistent banner also auto-clear when recording stops, or only on
   audio recovery?
   (Recommended: clear on audio recovery **or** when metering stops.)
   Answer: If there is no audio the banner must remain visible until the issue is resolved. The audio must be present prior to recording.

3. (New) Once Phase 5 removes the engine tap, should the code be deleted
   outright or kept behind a compile-time/runtime fallback flag for one release
   in case capture-output metering regresses on some device/OS combination in
   the field? Not sure. probably keep the code until we test.

4. ~~(New, 2026-08-28) **Does the meter under-read?**~~ **ANSWERED — no.** Once
   the `[meter]` trace logged peak alongside RMS, the apparent gap dissolved:
   crest factors are a normal 11–20 dB. The 30–45 dB figure came from comparing
   the meter's RMS against the file's peak, which is not a like-for-like
   comparison. The suspected "ch1 much quieter than ch2" case did occur, and has
   a mundane explanation — the operator was transmitting on TX2, leaving ch1 as
   an unpaired slot at digital zero. The meter is accurate.

5. (New, 2026-08-28)
   **The failing scenario was still not reproduced.**
   **Partially answered.** The _false "no audio" banner_ was reproduced,
   root-caused, and fixed — it was the silence watchdog, not the recording. The
   _silent recording_ remains unreproduced across five instrumented runs; every
   take contained audio. Still needed: a capture of a genuinely silent take.
   The most promising lead is now the `canAddInput`-failure path described in the
   candidate-mechanism note above, which would require forcing audio-input
   attachment to fail at session-configuration time (e.g. launching while
   another process holds the audio session) rather than manipulating the mic
   during a take.

6. (New, 2026-08-28) **Do Phases 2/3/5 still earn their cost?** They were
   designed to fix mis-binding and single-stream contention. Both were refuted on
   this hardware, and the meter now demonstrably agrees with the file to within
   ~2.5 dB. The remaining arguments for capture-output metering are architectural
   (one audio client instead of two) rather than bug-driven, and Phase 5 would
   retire engine-tap recovery logic that is currently working. Decide
   deliberately before starting.

   I
