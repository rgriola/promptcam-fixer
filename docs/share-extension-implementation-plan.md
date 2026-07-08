# Share Extension for PromptCam — Implementation Plan

**Created:** July 7, 2026
**Goal:** Make PromptCam a share destination so users can send content (script text or videos) from other apps INTO PromptCam via the iOS Share Sheet.

---

## Overview

Add a Share Extension target so PromptCam appears in the iOS Share Sheet from any app. Support two flows:

- **Primary — Import script text** (high value, simple): user shares text from Notes / Mail / Slack / Safari → PromptCam extension shows a mini "Save as Script" sheet → text lands in the teleprompter, ready to record
- **Secondary — Import video for review** (less common, more plumbing): user shares a video from Photos / Files / AirDrop → PromptCam adds it to the recordings library

Both flows use the same extension target — the activation rule filters what content types trigger which UI.

---

## Why This Matters for PromptCam

Right now, getting a script into the app requires typing or pasting into the compose sheet. With this feature:

- Reporter writes a script in Notes on their desk → shares to PromptCam on their phone → walks outside → hits record
- Producer emails a script → recipient long-presses text in Mail → shares to PromptCam → done
- Video from a colleague arrives via AirDrop → shares to PromptCam → shows up in the carousel for review

This is the workflow gap that Share Extensions were built for.

---

## Background: How iOS Share Extensions Work

A Share Extension is a **separate binary** shipped inside the main app bundle at `MyApp.app/PlugIns/MyAppShareExtension.appex`. When the user taps your app in another app's Share Sheet, iOS:

1. Launches the extension in its own sandboxed process (not the main app)
2. Hands it the shared content (files, URLs, text, video) via `NSExtensionContext`
3. Shows either the default compose UI or a custom UI
4. When the user taps Save/Send, the extension code runs
5. Extension exits

The main app doesn't launch unless the extension explicitly deep-links to it. To share data with the main app, use an **App Group** (shared file container) or a **URL scheme deep link**.

---

## Design Decisions

| Question                  | Answer                                                | Rationale                                                   |
| ------------------------- | ----------------------------------------------------- | ----------------------------------------------------------- |
| **Extension bundle name** | "PromptCam" (matches main app)                        | Consistent with Slack/Notes pattern                         |
| **Extension icon**        | Same as main app                                      | iOS uses main app icon by default                           |
| **UI style**              | Custom SwiftUI (not `SLComposeServiceViewController`) | Modern; matches the app's existing look                     |
| **Deep-link scheme**      | `promptcam://import?type=script&id=<uuid>`            | Extension writes payload → main app reads by ID             |
| **App Group ID**          | `group.com.rgriola.promptcam`                         | Shared container between extension + main app               |
| **Memory ceiling**        | ~120 MB (iOS limit)                                   | Videos must be moved via file URL, never loaded into memory |
| **Custom UTIs**           | None initially                                        | Public types (video, text, URL) cover 95% of use cases      |

---

## Activation Rules

The `NSExtensionActivationRule` in the extension's `Info.plist` decides which "Share..." menus light up PromptCam's icon:

```xml
<key>NSExtensionActivationRule</key>
<dict>
    <key>NSExtensionActivationSupportsMovieWithMaxCount</key>
    <integer>1</integer>
    <key>NSExtensionActivationSupportsText</key>
    <true/>
    <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
    <integer>1</integer>
    <key>NSExtensionActivationSupportsFileWithMaxCount</key>
    <integer>1</integer>
</dict>
```

Translation: PromptCam appears in the Share Sheet whenever the user is sharing:

- 1 video, OR
- Any text, OR
- 1 URL, OR
- 1 file (for `.txt` / `.rtf` scripts)

Explicitly NOT supported (initially): images, multi-file sharing, contacts.

---

## Phased Implementation

### Phase 1 — Foundation (project plumbing, no user-facing behavior yet)

**Scope**

1. Add a new App Extension target in Xcode: `PromptCamShareExtension`
2. Register in `project.yml` (XcodeGen) so regeneration includes it
3. Create an App Group capability shared between main app and extension
4. Add helper class `SharedContainer` in the main app for reading/writing the shared directory
5. Add a URL scheme `promptcam://` for deep-linking back to the main app
6. Set the extension's `NSExtensionActivationRule`
7. Empty extension body — accepts share, immediately dismisses. Just proves the plumbing works.

**Files new**

| File                                                           | Purpose                              |
| -------------------------------------------------------------- | ------------------------------------ |
| `PromptCamShareExtension/ShareViewController.swift`            | Extension entry point (empty stub)   |
| `PromptCamShareExtension/Info.plist`                           | Activation rule + extension identity |
| `PromptCamShareExtension/PromptCamShareExtension.entitlements` | App Group membership                 |
| `PromptCam/Services/SharedContainer.swift`                     | Reads/writes App Group container     |

**Files modified**

| File                     | Change                                                 |
| ------------------------ | ------------------------------------------------------ |
| `project.yml`            | Add new target + App Group entitlement to both targets |
| `PromptCam.entitlements` | Add App Group                                          |
| `PromptCam/Info.plist`   | Add `CFBundleURLTypes` for `promptcam://` scheme       |

**Tests**

- `SharedContainerTests`: verifies read/write round-trip in a mocked container URL
- Manual: install app → open Photos → verify PromptCam appears in Share Sheet → tap it → extension dismisses cleanly (no data yet)

**Exit criterion:** PromptCam shows up in the Share Sheet from Photos and Notes. Tapping does nothing user-visible but no crashes.

---

### Phase 2 — Import Script Text (the high-value flow)

**Scope**

1. Detect text / URL payload in `ShareViewController`
2. Present a custom SwiftUI sheet: "Save as Script" — shows a preview of the text, Save / Cancel buttons
3. On Save: write text to shared container as `pending-script-<uuid>.txt`
4. Open main app via `promptcam://import?type=script&id=<uuid>`
5. Main app: handle deep link in `PromptCamApp.onOpenURL`; load pending script into teleprompter via `CameraViewModel.importScript(from:)`
6. Delete the pending file after successful import

**Files new**

| File                                                     | Purpose                     |
| -------------------------------------------------------- | --------------------------- |
| `PromptCamShareExtension/ScriptImportView.swift`         | SwiftUI preview + Save UI   |
| `PromptCamShareExtension/ShareViewController+Text.swift` | Text/URL payload extraction |
| `PromptCam/Services/DeepLinkHandler.swift`               | Routes `promptcam://` URLs  |

**Files modified**

| File                                         | Change                                          |
| -------------------------------------------- | ----------------------------------------------- |
| `PromptCam/App/PromptCamApp.swift`           | Add `.onOpenURL` → `DeepLinkHandler.handle(_:)` |
| `PromptCam/ViewModels/CameraViewModel.swift` | Add `importScript(text:)` method                |

**Tests**

- `SharedContainerTests`: extend with script-save + script-read round-trip
- `DeepLinkHandlerTests`: parse well-formed and malformed URLs; verify script ID extraction; ignore unknown scheme paths
- `CameraViewModelImportScriptTests`: verify `importScript(text:)` updates the config text and triggers `resetTeleprompterPosition`
- Manual: paste a script in Notes → Share → PromptCam → verify text opens in teleprompter, ready to scroll

**Exit criterion:** User can share text from any app and it ends up loaded as the current teleprompter script within 2 seconds.

---

### Phase 3 — Import Video for Review (secondary flow)

**Scope**

1. Detect video payload in `ShareViewController` (`kUTTypeMovie`)
2. Present a different SwiftUI sheet: "Save to PromptCam" — shows video thumbnail + duration, Save / Cancel
3. Get the file URL from the `NSItemProvider`
4. Copy the video to the App Group's shared container (extension can't write to the main app's Documents directly)
5. Open main app via `promptcam://import?type=video&id=<uuid>`
6. Main app: reads the pending video from shared container, saves to Photo Library via existing `PhotoLibrarySaver` (already exists — free reuse), refreshes carousel
7. Delete the pending file

**Files new**

| File                                                      | Purpose                                 |
| --------------------------------------------------------- | --------------------------------------- |
| `PromptCamShareExtension/VideoImportView.swift`           | SwiftUI preview + Save UI               |
| `PromptCamShareExtension/ShareViewController+Video.swift` | Video payload extraction + copy         |
| `PromptCam/Services/VideoImportCoordinator.swift`         | Handles the video-import deep link path |

**Files modified**

| File                                       | Change                                                   |
| ------------------------------------------ | -------------------------------------------------------- |
| `PromptCam/Services/DeepLinkHandler.swift` | Route `type=video` to `VideoImportCoordinator`           |
| `PromptCam/Services/SharedContainer.swift` | Add video-specific helpers (URL generation, size checks) |

**Tests**

- `SharedContainerTests`: video-file round-trip; delete-after-import
- `VideoImportCoordinatorTests`: verify handoff to `PhotoLibrarySaver` (mockable — we already have the seam)
- Manual matrix: small video, large video (>120 MB extension limit), AirDrop, cancel-midway

**Exit criterion:** User can share any video from another app and it appears in the PromptCam recordings carousel within 5 seconds.

---

### Phase 4 — Polish & App Review Prep

**Scope**

1. Extension icon + display name copy audit (what shows in the Share Sheet)
2. Loading states: extension can be sluggish on first launch; add a spinner
3. Error handling: friendly error if App Group write fails
4. Privacy manifest updates for the extension (iOS 17+)
5. App Store screenshots showing the share flow
6. Extension-specific privacy string for Photos access

**Exit criterion:** Extension is production-quality and ready for App Store submission.

---

## Testing Strategy

### Unit tests (per phase)

Follows the same pattern as the recent library-refresh work — inject seams for anything that touches iOS internals:

- `SharedContainerObservable` protocol → mock in tests
- `DeepLinkHandler` operates on `URL` inputs — trivially testable
- `PhotoLibrarySaver` (already exists) — reused for video import
- Extension VC UI logic tested via testable ViewModel objects — the SwiftUI views are thin

### Integration tests (manual matrix)

| #   | Scenario                                          | Expected                                              |
| --- | ------------------------------------------------- | ----------------------------------------------------- |
| 1   | Share plain text from Notes                       | Script loads in teleprompter                          |
| 2   | Share URL from Safari                             | Page text extracted as script (Phase 2b — stretch)    |
| 3   | Share `.txt` file from Files                      | Same as text                                          |
| 4   | Share small video from Photos                     | Appears in carousel within 5 s                        |
| 5   | Share large video (>500 MB)                       | Either succeeds or shows friendly error — no crash    |
| 6   | Cancel extension midway                           | No leftover files, no crash on next share             |
| 7   | Share while main app is backgrounded              | Deep link launches main app, imports correctly        |
| 8   | Share while main app is foregrounded              | Main app receives deep link, imports without relaunch |
| 9   | Grant/deny Photos permission on first video share | Correct flow either way                               |
| 10  | Share from lock screen (via Camera app)           | Handled gracefully                                    |

### Regression coverage

- Existing 10 test suites must all still pass
- Recording flow must remain unaffected
- `PhotoLibraryChangeMonitor` will auto-refresh the carousel when Phase 3 saves a video — free integration

---

## App Store / Review Considerations

- **App Review reviews extensions separately** from the main app — expect ~24 hours extra review time on first submission.
- **Extension memory limit** — 120 MB. Videos must be moved via file URL, never loaded into memory.
- **Extension entitlements** must be a subset of the main app's — App Groups only for the extension.
- **Privacy strings** — extension needs its own `NSPhotoLibraryUsageDescription` if reading video metadata.
- **iCloud videos** — some Photos aren't on device. Needs `PHVideoRequestOptionsVersion.current` + `isNetworkAccessAllowed = true` (Phase 3).

---

## Estimated Effort

| Phase            | Complexity  | New files  | Modified         | Tests                         | Time (focused)      |
| ---------------- | ----------- | ---------- | ---------------- | ----------------------------- | ------------------- |
| 1 — Foundation   | Low         | 4          | 3                | 1 suite (~4 tests)            | Half day            |
| 2 — Script text  | Medium      | 3          | 2                | 3 suites (~10 tests)          | Full day            |
| 3 — Video import | Medium-high | 3          | 2                | 2 suites (~6 tests)           | Full day            |
| 4 — Polish       | Low         | 0          | ~5               | Manual matrix                 | Half day            |
| **Total**        | —           | **10 new** | **~12 modified** | **~20 tests + manual matrix** | **~3 days focused** |

---

## Questions Before Implementation

1. **Which phase is highest priority?** Phase 1 + Phase 2 (script text import) is the killer feature. Phase 3 is nice-to-have. Phase 4 is required for App Store submission.
2. **Deep link vs foreground handoff?** Deep-linking always launches the main app. Alternative: extension writes to shared container silently and only opens main app if it's not already running (Slack-style).
3. **URL sharing behavior?** Share a URL from Safari — use the URL as script, fetch the page and extract text, or skip URL support in Phase 2?
4. **Video import destination?** Photo Library (via existing `PhotoLibrarySaver`), app's private Documents, or both?
5. **Multiple scripts?** Currently one active teleprompter script. Overwrite, queue in a new "scripts library," or prompt user each time?

---

## Recommended Path

**Ship Phase 1 + Phase 2 first.** The script-import flow is small, high-value, and doesn't touch any existing app logic. Manual test extensively, then decide if Phase 3 (video import) is worth the additional plumbing based on user demand.

---

**Ready for approval.** Once confirmed, implement Phase 1 first (foundation only), verify the extension shows up in the Share Sheet, then proceed to Phase 2.
