# Custom Recordings Library Implementation Guide

> **Goal:** Replace the native `.photosPicker` with a custom in-app recordings library that mirrors the reference UI — a flat camera-roll grid, a single-video viewer with the system's built-in playback chrome plus three floating action buttons, and the standard iOS share sheet.

## Scope (decided up front)

1. **Grid.** Flat 3-column grid of every video in the user's library, newest first. No date filtering, no section headers, no app-only album scoping.
2. **Viewer.** SwiftUI `VideoPlayer` (provides play / pause / scrubber / time / volume out of the box) with three floating overlay buttons: close (top-left), share (top-right area), trash (top-right). No custom playback chrome.
3. **Sharing.** Standard iOS share sheet via `ShareLink`, attaching the actual video file (so iMessage / AirDrop / Files receive a playable `.mov`/`.mp4`, not a URL string). Backed by a `Transferable` wrapper and a `PHAssetResourceManager` export so iCloud-only assets download first.
4. **Delete.** In-place delete via `PHPhotoLibrary.performChanges`, gated by a confirmation dialog. Removes from the user's photo library and from the grid.
5. **Styling.** `Theme.bgGrad` background, existing tokens from [PromptCam/App/Theme.swift](PromptCam/App/Theme.swift). No new Theme tokens.
6. **Concurrency.** Swift 6 strict concurrency is enabled in [project.yml](project.yml). The service is a plain `Sendable struct`, not `@MainActor`.
7. **Deployment target.** iOS 18 — `Transferable`, `ShareLink`, `@Observable`, `VideoPlayer`, and `confirmationDialog` are all available.

**Explicitly out of scope for v1:** 7-day filter, section headers (Today / Yesterday), multi-select, in-app trim, custom playback bar, dedicated "PromptCam" album. Each is easy to bolt on later without rewrites.

---

## Phase 1: Data Layer (Models & Services)

### Step 1.1: Create Recording Model

**File:** `PromptCam/Models/Recording.swift`

```swift
import Photos
import UIKit

/// Lightweight, Sendable view model of a video recording.
/// Does NOT store the PHAsset reference — look it up on demand by localIdentifier
/// so the model can cross actor boundaries cleanly under Swift 6 strict concurrency.
struct Recording: Identifiable, Hashable, Sendable {
    let id: String          // PHAsset.localIdentifier
    let duration: TimeInterval
    let creationDate: Date
    let pixelWidth: Int
    let pixelHeight: Int

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.duration = asset.duration
        self.creationDate = asset.creationDate ?? Date()
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

`PromptCam/**` in [project.yml](project.yml) picks the new file up on the next `xcodegen generate`.

---

### Step 1.2: Create Recordings Service

**File:** `PromptCam/Services/RecordingsService.swift`

Key constraints baked in below:

- **Not `@MainActor`.** `PHAsset.fetchAssets` is thread-safe; making the service main-actor-isolated and then hopping to a global queue triggers `sending` violations under Swift 6 strict concurrency (see user memory note on `withTaskGroup` + `@MainActor`).
- Fetches **all** videos in the user's library, newest first. No date predicate.
- Uses a shared `PHCachingImageManager` so scrolling stays cheap.
- `exportForSharing` writes the original file bytes to a temp URL via `PHAssetResourceManager.writeData(for:toFile:)` so `ShareLink` attaches the file (iMessage / AirDrop) instead of a URL string, and so iCloud-only assets download first.

```swift
import AVFoundation
import Photos
import UIKit

/// Fetches and manages video recordings stored in the photo library.
struct RecordingsService: Sendable {

    /// Shared caching image manager for grid thumbnails.
    static let cachingManager = PHCachingImageManager()

    /// Fetches every video in the user's library, newest first.
    func fetchAllRecordings() async -> [Recording] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            Log.recordings.info("Photo library not authorized (\(status.rawValue, privacy: .public))")
            return []
        }

        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let fetch = PHAsset.fetchAssets(with: .video, options: options)
            var out: [Recording] = []
            out.reserveCapacity(fetch.count)
            fetch.enumerateObjects { asset, _, _ in out.append(Recording(asset: asset)) }
            return out
        }.value
    }

    /// Resolves a recording id back to its underlying `PHAsset`.
    private func asset(for id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Thumbnail via the shared caching manager. Skips the opportunistic
    /// degraded delivery so the cell paints exactly once with the final image.
    func thumbnail(for recording: Recording, targetSize: CGSize) async -> UIImage? {
        guard let asset = asset(for: recording.id) else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            Self.cachingManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded { continuation.resume(returning: image) }
            }
        }
    }

    /// Pre-warm thumbnails for visible cells.
    func startCaching(ids: [String], targetSize: CGSize) {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { a, _, _ in assets.append(a) }
        Self.cachingManager.startCachingImages(
            for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    func stopCachingAll() {
        Self.cachingManager.stopCachingImagesForAllAssets()
    }

    /// Exports the asset to a temp file URL so it can be shared via iMessage,
    /// AirDrop, Files, etc. Reuses a cached copy on repeat shares.
    func exportForSharing(_ recording: Recording) async -> URL? {
        guard let asset = asset(for: recording.id) else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .video })
                ?? resources.first else { return nil }

        let ext: String = {
            let raw = (resource.originalFilename as NSString).pathExtension
            return raw.isEmpty ? "mov" : raw
        }()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptCam-\(abs(recording.id.hashValue)).\(ext)")

        if FileManager.default.fileExists(atPath: url.path) { return url }

        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(
                for: resource, toFile: url, options: opts
            ) { error in
                if let error {
                    Log.recordings.error("export failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: url)
                }
            }
        }
    }

    /// Deletes the recording from the user's photo library.
    func deleteRecording(_ recording: Recording) async -> Bool {
        guard let asset = asset(for: recording.id) else { return false }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            } completionHandler: { success, error in
                if let error {
                    Log.recordings.error("delete failed: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: success)
            }
        }
    }
}
```

### Step 1.3: Add a `recordings` logger category

**File to modify:** [PromptCam/App/Log.swift](PromptCam/App/Log.swift)

```swift
static let recordings = Logger(subsystem: subsystem, category: "Recordings")
```

All trace output in the new code routes through `Log.recordings` (or existing `Log.ui` / `Log.viewmodel`) — no `print` calls.

---

## Phase 2: View Model

### Step 2.1: Create RecordingsLibraryViewModel

**File:** `PromptCam/ViewModels/RecordingsLibraryViewModel.swift`

Matches the codebase convention (`@Observable` + `@State`, **not** `ObservableObject` + `@StateObject`).

```swift
import Photos
import SwiftUI

@MainActor
@Observable
final class RecordingsLibraryViewModel {
    private(set) var recordings: [Recording] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let service = RecordingsService()
    private let permissions = PermissionService()

    var hasAccess: Bool {
        let status = permissions.photoLibraryStatus
        return status == .authorized || status == .limited
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        guard hasAccess else {
            recordings = []
            return
        }

        recordings = await service.fetchAllRecordings()
        Log.recordings.info("Loaded \(self.recordings.count, privacy: .public) recordings")
    }

    func thumbnail(for r: Recording, size: CGSize) async -> UIImage? {
        await service.thumbnail(for: r, targetSize: size)
    }

    func exportForSharing(_ r: Recording) async -> URL? {
        await service.exportForSharing(r)
    }

    func startCaching(ids: [String], size: CGSize) {
        service.startCaching(ids: ids, targetSize: size)
    }

    func stopCaching() {
        service.stopCachingAll()
    }

    func delete(_ recording: Recording) async {
        let ok = await service.deleteRecording(recording)
        if ok {
            recordings.removeAll { $0.id == recording.id }
        } else {
            errorMessage = "Failed to delete recording"
        }
    }
}
```

---

## Phase 3: UI Components

### Step 3.1: Recording thumbnail cell

**File:** `PromptCam/Views/Recordings/RecordingThumbnailView.swift`

Square cells (Photos-style) with `.aspectRatio(1, contentMode: .fit)` to maintain proper proportions. Images use `.scaledToFill()` so portrait videos crop to fill the square without stretching. Duration pill bottom-right. All Theme tokens referenced exist in [PromptCam/App/Theme.swift](PromptCam/App/Theme.swift).

```swift
import SwiftUI

struct RecordingThumbnailView: View {
    let recording: Recording
    let thumbnail: UIImage?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Theme.black

                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView().tint(Theme.primaryText)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(recording.formattedDuration)
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, Theme.space8)
                            .padding(.vertical, Theme.space4)
                            .background(.black.opacity(0.65),
                                        in: RoundedRectangle(cornerRadius: Theme.radiusSm))
                            .padding(Theme.space4)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        }
        .buttonStyle(.plain)
    }
}
```

---

### Step 3.2: Player with file-based sharing

**File:** `PromptCam/Views/Recordings/RecordingPlayerView.swift`

Uses SwiftUI's `VideoPlayer` for **all** playback chrome (play / pause / scrubber / time / volume). Only three themed buttons float on top: close (top-left), share and trash (top-right). Sharing routes through the standard iOS share sheet via `ShareLink` and a `VideoFile: Transferable` wrapper so iMessage / AirDrop / Files receive the actual file.

```swift
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct RecordingPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let recording: Recording
    let videoURL: URL?
    let onDelete: () -> Void

    @State private var player: AVPlayer?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if let videoURL {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        let p = AVPlayer(url: videoURL)
                        player = p
                        p.play()
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
            } else {
                VStack(spacing: Theme.space16) {
                    ProgressView().tint(Theme.primaryText)
                    Text("Loading video…")
                        .font(Theme.font16Regular)
                        .foregroundStyle(Theme.primaryText)
                }
            }

            HStack(spacing: Theme.space16) {
                Button { dismiss() } label: {
                    controlIcon("xmark.circle.fill", tint: Theme.primaryText)
                }
                Spacer()
                shareButton
                Button { showDeleteConfirmation = true } label: {
                    controlIcon("trash.circle.fill", tint: Theme.red)
                }
            }
            .padding(.horizontal, Theme.space16)
            .padding(.top, Theme.space8)
        }
        .confirmationDialog(
            "Delete Recording",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recording will be permanently deleted from your photo library.")
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let videoURL {
            ShareLink(
                item: VideoFile(url: videoURL),
                preview: SharePreview(recording.formattedDuration)
            ) {
                controlIcon("square.and.arrow.up.circle.fill", tint: Theme.primaryText)
            }
        } else {
            controlIcon("square.and.arrow.up.circle.fill", tint: Theme.secondaryText)
        }
    }

    private func controlIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 32))
            .foregroundStyle(tint)
            .shadow(color: .black.opacity(0.3), radius: 4)
    }
}

/// Wraps a video file URL so `ShareLink` attaches the file (iMessage / AirDrop /
/// Files) instead of sharing a URL string.
struct VideoFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) }
    }
}
```

---

### Step 3.3: Library sheet (flat grid + permissions)

**File:** `PromptCam/Views/Sheets/RecordingsLibrarySheet.swift`

Matches the reference UI: a single flat 3-column grid with 1pt spacing (edge-to-edge, no padding), dark nav bar titled `Camera Roll`, `Theme.bgGrad` background, plus a permission-denied state.

```swift
import Photos
import SwiftUI

struct RecordingsLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RecordingsLibraryViewModel()
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selectedRecording: Recording?
    @State private var shareURL: URL?
    @State private var showPlayer = false

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 1), count: 3
    )

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGrad.ignoresSafeArea()

                if !viewModel.hasAccess {
                    permissionDeniedView
                } else if viewModel.recordings.isEmpty && !viewModel.isLoading {
                    emptyStateView
                } else {
                    grid
                }
            }
            .navigationTitle("Camera Roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .task {
                await viewModel.load()
                warmThumbnails()
            }
            .onDisappear { viewModel.stopCaching() }
            .sheet(isPresented: $showPlayer) {
                if let r = selectedRecording {
                    RecordingPlayerView(
                        recording: r,
                        videoURL: shareURL,
                        onDelete: { Task { await viewModel.delete(r) } }
                    )
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) { Button("OK", role: .cancel) {} }
            message: { Text(viewModel.errorMessage ?? "") }
        }
        .presentationBackground(Theme.bgGrad)
    }

    // MARK: - Subviews

    private var permissionDeniedView: some View {
        VStack(spacing: Theme.space16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.secondaryText)
            Text("Photo Library Access Needed")
                .font(Theme.font20Semibold)
                .foregroundStyle(Theme.primaryText)
            Text("Enable photo library access in Settings to review your recordings.")
                .font(Theme.font12Regular)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(Theme.blackText)
        }
        .padding(Theme.space32)
    }

    private var emptyStateView: some View {
        VStack(spacing: Theme.space16) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundStyle(Theme.secondaryText)
            Text("No Videos")
                .font(Theme.font20Semibold)
                .foregroundStyle(Theme.primaryText)
            Text("Videos in your photo library will appear here.")
                .font(Theme.font12Regular)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.space32)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(viewModel.recordings) { recording in
                    RecordingThumbnailView(
                        recording: recording,
                        thumbnail: thumbnails[recording.id],
                        onTap: { open(recording) }
                    )
                    .task { await loadThumbnailIfNeeded(recording) }
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView().tint(Theme.primaryText)
            }
        }
    }

    // MARK: - Helpers

    private func open(_ recording: Recording) {
        selectedRecording = recording
        shareURL = nil
        Task {
            shareURL = await viewModel.exportForSharing(recording)
            showPlayer = true
        }
    }

    private func loadThumbnailIfNeeded(_ recording: Recording) async {
        guard thumbnails[recording.id] == nil else { return }
        let size = CGSize(width: 300, height: 300)
        if let image = await viewModel.thumbnail(for: recording, size: size) {
            thumbnails[recording.id] = image
        }
    }

    private func warmThumbnails() {
        let ids = viewModel.recordings.prefix(60).map(\.id)
        viewModel.startCaching(ids: Array(ids), size: CGSize(width: 300, height: 300))
    }
}
```

---

## Phase 4: Integration

### Step 4.1: Update CameraViewModel

**File:** [PromptCam/ViewModels/CameraViewModel.swift](PromptCam/ViewModels/CameraViewModel.swift)

The current enum is **`CameraSheetRoute`** with cases `.formatPanel`, `.composeScript`, `.settings` (top of the file). The recordings library becomes a fourth case routed through the existing `presentSheet(_:)` modal-queue logic, so the legacy `isPhotoPickerPresented` plumbing can go away.

1. Add the new case:

   ```swift
   enum CameraSheetRoute: String, Identifiable, Sendable {
       case formatPanel
       case composeScript
       case settings
       case recordingsLibrary   // ← add
       var id: String { rawValue }
   }
   ```

2. **Delete** the following properties / helpers because nothing else uses them once the picker is gone:
   - `var isPhotoPickerPresented = false`
   - `@ObservationIgnored private var queuedPhotoPicker = false`
   - `func handlePhotoPickerStateChanged(_ newValue: Bool)`

3. Replace `openPhotoLibrary()` with a simple route through the existing presenter:

   ```swift
   func openPhotoLibrary() {
       presentSheet(.recordingsLibrary)
   }
   ```

4. Simplify `presentSheet(_:)` and `presentQueuedModalIfNeeded()` by removing every branch that references `isPhotoPickerPresented` / `queuedPhotoPicker`. Both become straight `activeSheet` checks plus the existing `queuedSheet` dequeue.

### Step 4.2: Update CameraView Sheet Routing

**File:** [PromptCam/Views/CameraView.swift](PromptCam/Views/CameraView.swift)

1. Remove `@State private var selectedMediaItem: PhotosPickerItem?`.
2. Remove the entire `.photosPicker(isPresented: $viewModel.isPhotoPickerPresented, …)` modifier.
3. Remove `.onChange(of: selectedMediaItem)` and `.onChange(of: viewModel.isPhotoPickerPresented)` blocks.
4. Remove `import PhotosUI` (no longer used).
5. Add the new route to `sheetContent(for:)`:

   ```swift
   @ViewBuilder
   private func sheetContent(for route: CameraSheetRoute) -> some View {
       switch route {
       case .formatPanel:
           CameraFormatPanelSheet( /* unchanged */ )
       case .composeScript:
           ComposeScriptSheet( /* unchanged */ )
       case .settings:
           CameraSettingsSheet { viewModel.dismissActiveSheet() }
       case .recordingsLibrary:
           RecordingsLibrarySheet()
       }
   }
   ```

The footer button in [CameraFooterControlsView](PromptCam/Views/Camera/CameraFooterControlsView.swift) already calls `viewModel.openPhotoLibrary()`, so no change is needed there.

---

## Phase 5: Testing Checklist

### Permissions

- [ ] Authorized: grid populates with the user's videos
- [ ] Limited: only shared videos appear, grid still works
- [ ] Denied: lock icon + "Open Settings" CTA, no crash
- [ ] After granting access and relaunching, the grid refreshes

### Fetching

- [ ] Every video in the library is returned, newest first
- [ ] No section headers — just a flat 3-column grid

### Thumbnails

- [ ] Cell paints once with the final image (degraded delivery skipped)
- [ ] Scrolling 100+ items stays smooth (caching warmed)
- [ ] No memory growth across repeated open/close (caching torn down on disappear)

### Playback

- [ ] Tapping a cell opens the player
- [ ] Video plays automatically
- [ ] AVPlayer is paused and nilled on dismiss

### Sharing

- [ ] Share sheet attaches the actual `.mov` / `.mp4` file (not a URL)
- [ ] iMessage send works on device
- [ ] AirDrop send works (recipient receives a playable file)
- [ ] iCloud-only assets download then share (test with "Optimize iPhone Storage" on)
- [ ] Repeated shares reuse the cached temp file

### Deletion

- [ ] Confirmation dialog appears
- [ ] Cancel preserves the asset
- [ ] Delete removes from grid _and_ from the photo library
- [ ] Empty-state appears when the last video is deleted

### Visual

- [ ] `Theme.bgGrad` visible behind grid and empty/denied states
- [ ] Navigation bar uses dark color scheme
- [ ] Typography uses only existing `Theme.font*` tokens

### Concurrency

- [ ] Build with strict concurrency clean — no `sending parameter risks data races` warnings
- [ ] No `@MainActor` hops to a global queue in `RecordingsService`

---

## Common Pitfalls

### 1. `@MainActor` service hopping to a background queue

Don't make `RecordingsService` `@MainActor` and then dispatch to `DispatchQueue.global` — Swift 6 strict concurrency flags this with `sending parameter risks data races`. Keep the service as a plain `struct` (or `actor`) and hop off-main via `Task.detached`.

### 2. `ShareLink(item: URL)` shares a URL string, not a file

For iMessage / AirDrop / Files to attach the actual video, wrap the file as a `Transferable` with `FileRepresentation(contentType: .movie)` and pass that to `ShareLink`.

### 3. iCloud-backed assets

`AVURLAsset.url` for an asset stored in iCloud may be a remote URL that's slow or fails to share. Always export via `PHAssetResourceManager.writeData(for:toFile:)` with `isNetworkAccessAllowed = true`.

### 4. Tap-to-toggle over `VideoPlayer`

`VideoPlayer` swallows taps for its own controls. Don't layer `.onTapGesture` on top — keep the close / share / delete bar permanently visible.

### 5. Conflicting aspect ratios

Use `.aspectRatio(1, contentMode: .fit)` on the cell container and `.scaledToFill()` on the image itself. This ensures square cells maintain proper proportions while images crop to fill without stretching. Don't use `.aspectRatio(contentMode: .fill)` on both the image and container — that causes distortion.

### 6. Unbounded thumbnail cache

Use `PHCachingImageManager` keyed to visible cells; call `stopCachingImagesForAllAssets()` on disappear. A raw `[String: UIImage]` dictionary that never evicts will grow unbounded.

### 7. `@Observable` vs `ObservableObject`

This codebase uses `@Observable` + `@State`. Don't reintroduce `@StateObject` / `@Published` for the new view model — match [CameraViewModel](PromptCam/ViewModels/CameraViewModel.swift).

### 8. Modal queue

`CameraViewModel.presentSheet` and `presentQueuedModalIfNeeded` already manage one-at-a-time presentation. Route the recordings sheet through `presentSheet(.recordingsLibrary)` instead of adding a parallel boolean toggle.

### 9. AVPlayer cleanup

Always pause and nil the `AVPlayer` in `.onDisappear`, otherwise the audio session and frame decoder keep running.

### 10. `Info.plist` keys

`NSPhotoLibraryUsageDescription` is set via [project.yml](project.yml) (`INFOPLIST_KEY_NSPhotoLibraryUsageDescription`). Re-run `xcodegen generate` after any project.yml change.

---

## Build & Test Commands

```bash
xcodegen generate
xcodebuild -project PromptCam.xcodeproj \
  -scheme PromptCam \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

xcodebuild test -project PromptCam.xcodeproj \
  -scheme PromptCam \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

> AirDrop and iMessage sharing cannot be exercised in the simulator — run Phase 5's sharing checks on a real device.

---

## File Summary

**New files (6):**

1. `PromptCam/Models/Recording.swift`
2. `PromptCam/Services/RecordingsService.swift`
3. `PromptCam/ViewModels/RecordingsLibraryViewModel.swift`
4. `PromptCam/Views/Recordings/RecordingThumbnailView.swift`
5. `PromptCam/Views/Recordings/RecordingPlayerView.swift` (includes the `VideoFile: Transferable` shim)
6. `PromptCam/Views/Sheets/RecordingsLibrarySheet.swift`

**Files to modify (3):**

1. [PromptCam/ViewModels/CameraViewModel.swift](PromptCam/ViewModels/CameraViewModel.swift) — add `.recordingsLibrary` case; remove `isPhotoPickerPresented` / `queuedPhotoPicker` / `handlePhotoPickerStateChanged`; rewrite `openPhotoLibrary()`; simplify `presentSheet` and `presentQueuedModalIfNeeded`.
2. [PromptCam/Views/CameraView.swift](PromptCam/Views/CameraView.swift) — remove `.photosPicker`, `selectedMediaItem`, both `.onChange` blocks, and `import PhotosUI`; add `.recordingsLibrary` case to `sheetContent(for:)`.
3. [PromptCam/App/Log.swift](PromptCam/App/Log.swift) — add `Log.recordings` category.

---

## Implementation Order

1. Phase 1 — Model + Service + `Log.recordings` category.
2. Phase 2 — `RecordingsLibraryViewModel`.
3. Phase 3 — Thumbnail, Player, Sheet.
4. Phase 4 — Wire into `CameraViewModel` + `CameraView`.
5. Phase 5 — Run the checklist on a real device.

---

## Notes

- All new code targets iOS 18 (per [project.yml](project.yml)), so `Transferable`, `ShareLink`, `@Observable`, `VideoPlayer`, and `confirmationDialog` are all available.
- Theme tokens referenced here all exist in [PromptCam/App/Theme.swift](PromptCam/App/Theme.swift): `bgGrad`, `black`, `primaryText`, `secondaryText`, `blackText`, `accent`, `red`, `radiusSm`, `space4`, `space8`, `space16`, `space32`, `font12Regular`, `font12Medium`, `font16Regular`, `font16Semibold`, `font20Semibold`.
- All trace output routes through `Log.recordings` (or existing `Log.ui` / `Log.viewmodel`), never `print`.
- Photo library permission prompts are already implemented in [PermissionService](PromptCam/Services/PermissionService.swift).

---

**Ready to implement?** Start with Phase 1 and work through sequentially. Each phase is independently testable.
