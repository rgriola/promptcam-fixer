Context & problem
PromptCam/ViewModels/CameraViewModel.swift is 766 lines / ~91 members in a single @MainActor @Observable final class. SwiftLint's type_body_length is configured at warning 300 / error 450 (.swiftlint.yml), so this type is ~1.7× over the hard error limit and is the app's clearest "god object." It mixes at least eight distinct responsibilities, the largest being setupAudioMeter() (~100 lines of nested callback wiring) and bindCallbacks() (~70 lines).

Hard constraint: the type is consumed by a single view, PromptCam/Views/CameraView.swift, through 58 unique viewModel.\* member references, and by PromptCamTests/CameraViewModelTests.swift (which injects MockCameraService via init). The refactor must preserve the public API surface and the DI init so neither the view nor the existing tests need rewriting (beyond mechanical path changes).

Goals
Bring the type under the SwiftLint type_body_length limits by decomposing responsibilities.
Keep behavior identical — this is a pure structural refactor, no functional changes.
Preserve CameraViewModel's public API (all 58 view-facing members) and its init(cameraService:permissionService:) signature.
Keep everything @MainActor and Swift 6 strict-concurrency clean (the project sets SWIFT_STRICT_CONCURRENCY: complete).
Keep or improve unit-test coverage; extracted units should be independently testable.
Non-goals
No change to CameraService / CameraServiceProtocol or the callback contract.
No UI/behavior changes, no new dependencies, no change to persistence keys or formats.
Not attempting to also split CameraService (a separate, already-noted concern in docs/opus-code-review-jun-15.md).
Responsibility inventory (what lives in the file today)
The implementing agent should treat these as the seams to split along:

Teleprompter state & style persistence — config, updateScriptText, updateTeleprompterStyle, cycleTextAlignment, resetTeleprompterPosition, teleprompterResetToken, saveStylePreferences/loadStylePreferences, the StyleKey enum (UserDefaults keys).
Recording lifecycle & timer — isRecording, toggleRecording, recordingDuration, startTimer/stopTimer, timerCancellable, recordingStartDate (Combine-based).
Audio metering & routing (largest) — all audio*/mic/gain/stereo/source-picker properties, setupAudioMeter, openAudioSourcePicker, selectAudioInput, setAudioGain, showSourceHint, audioMeterService.
Focus / exposure / aperture — lockStatus, focus, lockFocusExposure, unlockFocusExposure, setSimulatedAperture, adjustExposure, setExposure, cinematicApertureRange, cinematicSimulatedAperture, plus the CameraLockStatus enum + init(outcome:) extension.
Recordings carousel / direct player — latestRecording, latestVideoURL, recentRecordings, showDirectPlayer, prefetchLatestRecording, warmCarouselCache, refreshLatestRecording, openDirectPlayer, openPhotoLibrary, recordingsService, photoLibraryMonitor.
Modal / sheet queue — activeSheet, queuedSheet, lastPresentedSheet, presentSheet, presentQueuedModalIfNeeded, handleSheetStateChanged, dismissActiveSheet, plus the open* sheet methods and CameraSheetRoute enum.
Format & device capabilities — recordingFormat, deviceCapabilities, updateRecordingFormat.
Service callback binding — bindCallbacks (fans out to categories 2/3/4/7), lifecycle onAppear/onDisappear.
Recommended approach — extract child @Observable models, compose into CameraViewModel
Because the type is @Observable and consumed by one view, the cleanest decomposition is to pull cohesive slices into their own @MainActor @Observable sub-models that CameraViewModel owns and exposes, rather than trying to split one class across extension files (extensions do NOT reduce type_body_length, which counts the whole type body — so extensions alone will not fix the lint error).

Suggested extracted types (names illustrative — agent to finalize):

TeleprompterViewModel — responsibility 1. Owns config + style persistence. Pure, no camera dependency → easily unit-tested (mirrors existing TeleprompterConfigTests).
AudioMeterViewModel — responsibility 3. Owns the AudioMeterService and all audio published state + route/silence/gain logic. This is the single biggest win (~200 lines).
RecordingsCarouselViewModel — responsibility 5. Owns RecordingsService + PhotoLibraryChangeMonitor and the direct-player/carousel state.
CameraControlsViewModel (or FocusExposureViewModel) — responsibility 4. Focus/exposure/aperture/lock.
ModalRouter — responsibility 6. The sheet-queue state machine (already self-contained and well-documented; good candidate, and independently testable).
Keep responsibilities 2, 7, 8 (recording toggle/timer, format, and the bindCallbacks orchestration) in CameraViewModel as the coordinator, since they are the glue between the service and the child models.
API-preservation strategy (critical)
The view references flat members like viewModel.audioLevel, viewModel.openAudioSourcePicker, viewModel.config. Two options for the agent to choose between, in order of preference:

Option A (lowest churn): keep CameraViewModel's public surface, delegate internally. Add thin forwarding computed properties / methods on CameraViewModel that proxy to the child models (e.g. var audioLevel: Float { audio.audioLevel }). This preserves all 58 call sites and the tests verbatim, while the implementation body shrinks. Note: forwarding members still add to type_body_length, so favor moving whole clusters where the view can reference the child directly.
Option B (cleaner, more churn): expose child models and update CameraView. Make the children public let (e.g. viewModel.audio.audioLevel) and update the ~58 references in CameraView.swift. This yields the biggest reduction in the parent's body length but touches the view. Recommend doing this only for the audio cluster (largest) and keeping Option A for small clusters, to balance churn vs. lint headroom.
A pragmatic mix: extract the audio and recordings/carousel clusters as exposed child models (Option B) — that alone removes ~300 lines — and keep thin forwarding (Option A) for the smaller teleprompter/focus/modal clusters if needed to stay readable.

Suggested file layout
Split into files under PromptCam/ViewModels/ (XcodeGen globs the folder, so new files are picked up automatically on xcodegen generate — no project.yml edit needed):

CameraViewModel.swift — slimmed coordinator (init, DI, bindCallbacks, recording toggle/timer, format, lifecycle).
Camera/TeleprompterViewModel.swift
Camera/AudioMeterViewModel.swift
Camera/RecordingsCarouselViewModel.swift
Camera/CameraControlsViewModel.swift
Camera/ModalRouter.swift
Move the CameraSheetRoute, CameraMode, CameraLockStatus enums next to their owning types.
Step-by-step sequence (incremental, each step compiles & tests green)
Baseline safety net. Run the existing PromptCamTests (esp. CameraViewModelTests) to confirm green before touching anything. Note current SwiftLint type_body_length count for the file.
Extract the pure teleprompter cluster first (no service coupling, lowest risk). Move config + style persistence + StyleKey into TeleprompterViewModel; forward from CameraViewModel. Re-run tests.
Extract the modal router (self-contained state machine). Move sheet-queue logic; forward openCompose/openSettings/openFormatPanel/handleSheetStateChanged/dismissActiveSheet. Re-run tests.
Extract focus/exposure/aperture into CameraControlsViewModel; the bindCallbacks onCinematicApertureAvailable closure updates it. Re-run.
Extract recordings carousel / direct player. Move RecordingsService, PhotoLibraryChangeMonitor, prefetch/warm/refresh. Wire onRecordingSavedToLibrary + onRecordingStateChanged to it. Re-run.
Extract audio metering (biggest). Move AudioMeterService ownership and all audio state + setupAudioMeter. bindCallbacks's onSessionRunningStateChanged calls into it to attach the meter when the session starts. Re-run.
Slim the coordinator. CameraViewModel now holds child models, bindCallbacks (delegating to children), recording toggle/timer, format, onAppear/onDisappear. Confirm type_body_length is under 300 (warning) for every type.
Reconcile the view. Apply whichever of Option A/B was chosen; update CameraView.swift references only where a cluster was exposed directly. Verify no other view references the VM (grep confirmed only CameraView.swift does today).
Tests. Split/extend tests: keep CameraViewModelTests for coordinator behavior (recording toggle, format no-op while recording, error propagation) and add focused tests per extracted model where they weren't previously reachable (e.g. modal-queue transitions, style persistence round-trip). Reuse MockCameraService.
Validate. xcodegen generate, build, run PromptCamTests, run SwiftLint + SwiftFormat (.swiftlint.yml / .swiftformat). Confirm the new CI workflow (.github/workflows/ci.yml) passes.
Risks & things to watch
type_body_length counts the whole type, not the file — extensions/// MARK: reorganization alone will NOT clear the lint error. Real extraction into separate types is required.
@Observable observation must be preserved — child models must also be @MainActor @Observable so SwiftUI still re-renders when their properties change; the view must observe the actual object that owns each property (a plain forwarding computed property on the parent still triggers observation because the read happens through the parent, but exposing children directly is more robust — agent should verify with a quick runtime check).
Strict concurrency — all extracted types stay @MainActor; the service callbacks are already @MainActor @Sendable, so moving their bodies into child methods is safe. Watch @ObservationIgnored on stored services/tasks (audioSourceHintTask, timerCancellable, monitors) — preserve those attributes.
Callback ownership — bindCallbacks currently captures self weakly and fans out; after extraction it must forward to child models (still weakly) without creating retain cycles. The audioMeterService == nil guard that gates setupAudioMeter must move with the audio model.
Initialization order — child models must be constructed in init before bindCallbacks() runs; loadStylePreferences() currently runs in init and must move with the teleprompter model.
Single-consumer advantage — because only CameraView.swift and the tests touch the VM, blast radius is contained; lean into Option B for the big clusters.
Definition of done
Every type in the touched files is under SwiftLint type_body_length warning (300).
xcodegen generate + build succeed; all existing PromptCamTests pass unchanged in intent; new per-model tests added.
No behavioral diffs in CameraView (manual smoke of record, teleprompter style, format panel, audio source switch, direct player).
SwiftLint + SwiftFormat clean; CI green. </plan>
I explored the file (766 lines, ~91 members, single @Observable class), confirmed it's ~1.7× over SwiftLint's type_body_length error limit, mapped its eight responsibilities, and verified the coupling surface: only CameraView.swift consumes it (58 unique member refs) plus CameraViewModelTests via MockCameraService. The plan above is structured for a separate agent to execute incrementally with the test suite as a safety net. No code was changed.

Note: I verified the memory about signing config (Signing.xcconfig / configFiles) — it's accurate but not relevant to this refactor, so I didn't rely on it here.

Refactor Plan: CameraViewModel
Context & problem
PromptCam/ViewModels/CameraViewModel.swift is 766 lines / ~91 members in a single @MainActor @Observable final class. SwiftLint's type_body_length is configured at warning 300 / error 450 (.swiftlint.yml), so this type is ~1.7× over the hard error limit and is the app's clearest "god object." It mixes at least eight distinct responsibilities, the largest being setupAudioMeter() (~100 lines of nested callback wiring) and bindCallbacks() (~70 lines).

Hard constraint: the type is consumed by a single view, PromptCam/Views/CameraView.swift, through 58 unique viewModel.\* member references, and by PromptCamTests/CameraViewModelTests.swift (which injects MockCameraService via init). The refactor must preserve the public API surface and the DI init so neither the view nor the existing tests need rewriting (beyond mechanical path changes).

Goals
Bring the type under the SwiftLint type_body_length limits by decomposing responsibilities.
Keep behavior identical — this is a pure structural refactor, no functional changes.
Preserve CameraViewModel's public API (all 58 view-facing members) and its init(cameraService:permissionService:) signature.
Keep everything @MainActor and Swift 6 strict-concurrency clean (the project sets SWIFT_STRICT_CONCURRENCY: complete).
Keep or improve unit-test coverage; extracted units should be independently testable.
Non-goals
No change to CameraService / CameraServiceProtocol or the callback contract.
No UI/behavior changes, no new dependencies, no change to persistence keys or formats.
Not attempting to also split CameraService (a separate, already-noted concern in docs/opus-code-review-jun-15.md).
Responsibility inventory (what lives in the file today)
The implementing agent should treat these as the seams to split along:

Teleprompter state & style persistence — config, updateScriptText, updateTeleprompterStyle, cycleTextAlignment, resetTeleprompterPosition, teleprompterResetToken, saveStylePreferences/loadStylePreferences, the StyleKey enum (UserDefaults keys).
Recording lifecycle & timer — isRecording, toggleRecording, recordingDuration, startTimer/stopTimer, timerCancellable, recordingStartDate (Combine-based).
Audio metering & routing (largest) — all audio*/mic/gain/stereo/source-picker properties, setupAudioMeter, openAudioSourcePicker, selectAudioInput, setAudioGain, showSourceHint, audioMeterService.
Focus / exposure / aperture — lockStatus, focus, lockFocusExposure, unlockFocusExposure, setSimulatedAperture, adjustExposure, setExposure, cinematicApertureRange, cinematicSimulatedAperture, plus the CameraLockStatus enum + init(outcome:) extension.
Recordings carousel / direct player — latestRecording, latestVideoURL, recentRecordings, showDirectPlayer, prefetchLatestRecording, warmCarouselCache, refreshLatestRecording, openDirectPlayer, openPhotoLibrary, recordingsService, photoLibraryMonitor.
Modal / sheet queue — activeSheet, queuedSheet, lastPresentedSheet, presentSheet, presentQueuedModalIfNeeded, handleSheetStateChanged, dismissActiveSheet, plus the open* sheet methods and CameraSheetRoute enum.
Format & device capabilities — recordingFormat, deviceCapabilities, updateRecordingFormat.
Service callback binding — bindCallbacks (fans out to categories 2/3/4/7), lifecycle onAppear/onDisappear.
Recommended approach — extract child @Observable models, compose into CameraViewModel
Because the type is @Observable and consumed by one view, the cleanest decomposition is to pull cohesive slices into their own @MainActor @Observable sub-models that CameraViewModel owns and exposes, rather than trying to split one class across extension files (extensions do NOT reduce type_body_length, which counts the whole type body — so extensions alone will not fix the lint error).

Suggested extracted types (names illustrative — agent to finalize):

TeleprompterViewModel — responsibility 1. Owns config + style persistence. Pure, no camera dependency → easily unit-tested (mirrors existing TeleprompterConfigTests).
AudioMeterViewModel — responsibility 3. Owns the AudioMeterService and all audio published state + route/silence/gain logic. This is the single biggest win (~200 lines).
RecordingsCarouselViewModel — responsibility 5. Owns RecordingsService + PhotoLibraryChangeMonitor and the direct-player/carousel state.
CameraControlsViewModel (or FocusExposureViewModel) — responsibility 4. Focus/exposure/aperture/lock.
ModalRouter — responsibility 6. The sheet-queue state machine (already self-contained and well-documented; good candidate, and independently testable).
Keep responsibilities 2, 7, 8 (recording toggle/timer, format, and the bindCallbacks orchestration) in CameraViewModel as the coordinator, since they are the glue between the service and the child models.
API-preservation strategy (critical)
The view references flat members like viewModel.audioLevel, viewModel.openAudioSourcePicker, viewModel.config. Two options for the agent to choose between, in order of preference:

Option A (lowest churn): keep CameraViewModel's public surface, delegate internally. Add thin forwarding computed properties / methods on CameraViewModel that proxy to the child models (e.g. var audioLevel: Float { audio.audioLevel }). This preserves all 58 call sites and the tests verbatim, while the implementation body shrinks. Note: forwarding members still add to type_body_length, so favor moving whole clusters where the view can reference the child directly.
Option B (cleaner, more churn): expose child models and update CameraView. Make the children public let (e.g. viewModel.audio.audioLevel) and update the ~58 references in CameraView.swift. This yields the biggest reduction in the parent's body length but touches the view. Recommend doing this only for the audio cluster (largest) and keeping Option A for small clusters, to balance churn vs. lint headroom.
A pragmatic mix: extract the audio and recordings/carousel clusters as exposed child models (Option B) — that alone removes ~300 lines — and keep thin forwarding (Option A) for the smaller teleprompter/focus/modal clusters if needed to stay readable.

Suggested file layout
Split into files under PromptCam/ViewModels/ (XcodeGen globs the folder, so new files are picked up automatically on xcodegen generate — no project.yml edit needed):

CameraViewModel.swift — slimmed coordinator (init, DI, bindCallbacks, recording toggle/timer, format, lifecycle).
Camera/TeleprompterViewModel.swift
Camera/AudioMeterViewModel.swift
Camera/RecordingsCarouselViewModel.swift
Camera/CameraControlsViewModel.swift
Camera/ModalRouter.swift
Move the CameraSheetRoute, CameraMode, CameraLockStatus enums next to their owning types.
Step-by-step sequence (incremental, each step compiles & tests green)
Baseline safety net. Run the existing PromptCamTests (esp. CameraViewModelTests) to confirm green before touching anything. Note current SwiftLint type_body_length count for the file.
Extract the pure teleprompter cluster first (no service coupling, lowest risk). Move config + style persistence + StyleKey into TeleprompterViewModel; forward from CameraViewModel. Re-run tests.
Extract the modal router (self-contained state machine). Move sheet-queue logic; forward openCompose/openSettings/openFormatPanel/handleSheetStateChanged/dismissActiveSheet. Re-run tests.
Extract focus/exposure/aperture into CameraControlsViewModel; the bindCallbacks onCinematicApertureAvailable closure updates it. Re-run.
Extract recordings carousel / direct player. Move RecordingsService, PhotoLibraryChangeMonitor, prefetch/warm/refresh. Wire onRecordingSavedToLibrary + onRecordingStateChanged to it. Re-run.
Extract audio metering (biggest). Move AudioMeterService ownership and all audio state + setupAudioMeter. bindCallbacks's onSessionRunningStateChanged calls into it to attach the meter when the session starts. Re-run.
Slim the coordinator. CameraViewModel now holds child models, bindCallbacks (delegating to children), recording toggle/timer, format, onAppear/onDisappear. Confirm type_body_length is under 300 (warning) for every type.
Reconcile the view. Apply whichever of Option A/B was chosen; update CameraView.swift references only where a cluster was exposed directly. Verify no other view references the VM (grep confirmed only CameraView.swift does today).
Tests. Split/extend tests: keep CameraViewModelTests for coordinator behavior (recording toggle, format no-op while recording, error propagation) and add focused tests per extracted model where they weren't previously reachable (e.g. modal-queue transitions, style persistence round-trip). Reuse MockCameraService.
Validate. xcodegen generate, build, run PromptCamTests, run SwiftLint + SwiftFormat (.swiftlint.yml / .swiftformat). Confirm the new CI workflow (.github/workflows/ci.yml) passes.
Risks & things to watch
type_body_length counts the whole type, not the file — extensions/// MARK: reorganization alone will NOT clear the lint error. Real extraction into separate types is required.
@Observable observation must be preserved — child models must also be @MainActor @Observable so SwiftUI still re-renders when their properties change; the view must observe the actual object that owns each property (a plain forwarding computed property on the parent still triggers observation because the read happens through the parent, but exposing children directly is more robust — agent should verify with a quick runtime check).
Strict concurrency — all extracted types stay @MainActor; the service callbacks are already @MainActor @Sendable, so moving their bodies into child methods is safe. Watch @ObservationIgnored on stored services/tasks (audioSourceHintTask, timerCancellable, monitors) — preserve those attributes.
Callback ownership — bindCallbacks currently captures self weakly and fans out; after extraction it must forward to child models (still weakly) without creating retain cycles. The audioMeterService == nil guard that gates setupAudioMeter must move with the audio model.
Initialization order — child models must be constructed in init before bindCallbacks() runs; loadStylePreferences() currently runs in init and must move with the teleprompter model.
Single-consumer advantage — because only CameraView.swift and the tests touch the VM, blast radius is contained; lean into Option B for the big clusters.
Definition of done
Every type in the touched files is under SwiftLint type_body_length warning (300).
xcodegen generate + build succeed; all existing PromptCamTests pass unchanged in intent; new per-model tests added.
No behavioral diffs in CameraView (manual smoke of record, teleprompter style, format panel, audio source switch, direct player).
SwiftLint + SwiftFormat clean; CI green.
