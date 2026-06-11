# Custom Recordings Library Implementation Guide

> **Goal:** Replace native PhotosPicker with a custom recordings library that allows users to review, share, and manage their video recordings with a custom background.

---

## Phase 1: Data Layer (Models & Services)

### Step 1.1: Create Recording Model

**File:** `PromptCam/Models/Recording.swift`

```swift
// Recording.swift
import Photos
import UIKit

/// Represents a video recording from the photo library.
struct Recording: Identifiable, Hashable {
    let id: String  // PHAsset.localIdentifier
    let asset: PHAsset
    let duration: TimeInterval
    let creationDate: Date
    let pixelWidth: Int
    let pixelHeight: Int

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
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

    var aspectRatio: CGFloat {
        guard pixelHeight > 0 else { return 16.0 / 9.0 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Recording, rhs: Recording) -> Bool {
        lhs.id == rhs.id
    }
}
```

**Update:** `project.yml` will auto-include this via `PromptCam/**` sources glob. No manual Xcode project changes needed if using XcodeGen.

---

### Step 1.2: Create Recordings Service

**File:** `PromptCam/Services/RecordingsService.swift`

```swift
// RecordingsService.swift
import Photos
import UIKit

/// Service for fetching and managing video recordings from the photo library.
@MainActor
final class RecordingsService: ObservableObject {

    /// Fetches all video recordings from photo library, sorted by creation date (newest first).
    func fetchAllRecordings() async -> [Recording] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            print("[RecordingsService] Photo library access not authorized")
            return []
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)

                let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
                var recordings: [Recording] = []

                fetchResult.enumerateObjects { asset, _, _ in
                    recordings.append(Recording(asset: asset))
                }

                continuation.resume(returning: recordings)
            }
        }
    }

    /// Generates a thumbnail for a recording.
    func fetchThumbnail(for recording: Recording, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: recording.asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Exports a recording's video URL for sharing.
    func exportVideoURL(for recording: Recording) async -> URL? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(
                forVideo: recording.asset,
                options: options
            ) { avAsset, _, _ in
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: urlAsset.url)
            }
        }
    }

    /// Deletes a recording from the photo library.
    func deleteRecording(_ recording: Recording) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([recording.asset] as NSArray)
            } completionHandler: { success, error in
                if let error = error {
                    print("[RecordingsService] Delete failed: \(error)")
                }
                continuation.resume(returning: success)
            }
        }
    }
}
```

---

## Phase 2: View Models

### Step 2.1: Create RecordingsLibraryViewModel

**File:** `PromptCam/ViewModels/RecordingsLibraryViewModel.swift`

```swift
// RecordingsLibraryViewModel.swift
import SwiftUI
import Photos

/// View model for the recordings library screen.
@MainActor
final class RecordingsLibraryViewModel: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedRecording: Recording?

    private let service = RecordingsService()

    /// Loads recordings from photo library.
    func loadRecordings() async {
        isLoading = true
        errorMessage = nil

        do {
            recordings = await service.fetchAllRecordings()
            print("[RecordingsVM] Loaded \(recordings.count) recordings")
        } catch {
            errorMessage = "Failed to load recordings"
            print("[RecordingsVM] Error: \(error)")
        }

        isLoading = false
    }

    /// Fetches a thumbnail for display in the grid.
    func thumbnail(for recording: Recording, size: CGSize) async -> UIImage? {
        await service.fetchThumbnail(for: recording, targetSize: size)
    }

    /// Exports video URL for sharing.
    func videoURL(for recording: Recording) async -> URL? {
        await service.exportVideoURL(for: recording)
    }

    /// Deletes a recording.
    func deleteRecording(_ recording: Recording) async {
        let success = await service.deleteRecording(recording)
        if success {
            recordings.removeAll { $0.id == recording.id }
        } else {
            errorMessage = "Failed to delete recording"
        }
    }
}
```

---

## Phase 3: UI Components

### Step 3.1: Create Recording Thumbnail View

**File:** `PromptCam/Views/Recordings/RecordingThumbnailView.swift`

```swift
// RecordingThumbnailView.swift
import SwiftUI

/// Displays a single recording thumbnail in the grid.
struct RecordingThumbnailView: View {
    let recording: Recording
    let thumbnail: UIImage?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Thumbnail
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Theme.panelBg.opacity(0.3))
                    ProgressView()
                        .tint(Theme.primaryText)
                }

                // Play icon overlay
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 4)

                // Duration badge (bottom-right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(recording.formattedDuration)
                            .font(Theme.font12Medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.space8)
                            .padding(.vertical, Theme.space4)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                            .padding(Theme.space8)
                    }
                }
            }
            .aspectRatio(recording.aspectRatio, contentMode: .fit)
            .background(Theme.black)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        }
        .buttonStyle(.plain)
    }
}
```

---

### Step 3.2: Create Video Player View

**File:** `PromptCam/Views/Recordings/RecordingPlayerView.swift`

```swift
// RecordingPlayerView.swift
import SwiftUI
import AVKit

/// Full-screen video player for reviewing recordings.
struct RecordingPlayerView: View {
    @Environment(\.dismiss) var dismiss
    let recording: Recording
    let videoURL: URL?
    let onDelete: () -> Void

    @State private var player: AVPlayer?
    @State private var showControls = true
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let videoURL = videoURL {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        player = AVPlayer(url: videoURL)
                        player?.play()
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
            } else {
                VStack(spacing: Theme.space16) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading video...")
                        .font(Theme.font16Regular)
                        .foregroundStyle(.white)
                }
            }

            // Controls overlay
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .padding(Theme.space16)

                    Spacer()

                    if let videoURL = videoURL {
                        ShareLink(item: videoURL) {
                            Image(systemName: "square.and.arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 4)
                        }
                        .padding(Theme.space16)
                    }

                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.red)
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .padding(Theme.space16)
                }

                Spacer()
            }
            .opacity(showControls ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: showControls)
        }
        .onTapGesture {
            showControls.toggle()
        }
        .confirmationDialog(
            "Delete Recording",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recording will be permanently deleted from your photo library.")
        }
    }
}
```

---

### Step 3.3: Create Main Library Sheet

**File:** `PromptCam/Views/Sheets/RecordingsLibrarySheet.swift`

```swift
// RecordingsLibrarySheet.swift
import SwiftUI

/// Modal sheet displaying all video recordings in a grid layout.
struct RecordingsLibrarySheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = RecordingsLibraryViewModel()
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selectedRecording: Recording?
    @State private var videoURL: URL?
    @State private var showPlayer = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.recordings.isEmpty && !viewModel.isLoading {
                    emptyStateView
                } else {
                    recordingsGridView
                }
            }
            .navigationTitle("My Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.loadRecordings()
                await loadThumbnails()
            }
            .sheet(isPresented: $showPlayer) {
                if let recording = selectedRecording {
                    RecordingPlayerView(
                        recording: recording,
                        videoURL: videoURL,
                        onDelete: {
                            Task {
                                await viewModel.deleteRecording(recording)
                            }
                        }
                    )
                }
            }
        }
        .presentationBackground(Theme.bgGrad)
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: Theme.space16) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundStyle(Theme.secondaryText)

            Text("No Recordings")
                .font(Theme.font20Medium)
                .foregroundStyle(Theme.primaryText)

            Text("Your recorded videos will appear here")
                .font(Theme.font14Regular)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.space32)
    }

    private var recordingsGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.recordings) { recording in
                    RecordingThumbnailView(
                        recording: recording,
                        thumbnail: thumbnails[recording.id],
                        onTap: {
                            selectedRecording = recording
                            Task {
                                videoURL = await viewModel.videoURL(for: recording)
                                showPlayer = true
                            }
                        }
                    )
                    .aspectRatio(1, contentMode: .fill)
                }
            }
            .padding(2)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .tint(Theme.primaryText)
            }
        }
    }

    // MARK: - Helpers

    private func loadThumbnails() async {
        let size = CGSize(width: 300, height: 300)

        await withTaskGroup(of: (String, UIImage?).self) { group in
            for recording in viewModel.recordings {
                group.addTask {
                    let thumbnail = await viewModel.thumbnail(for: recording, size: size)
                    return (recording.id, thumbnail)
                }
            }

            for await (id, thumbnail) in group {
                if let thumbnail = thumbnail {
                    thumbnails[id] = thumbnail
                }
            }
        }
    }
}
```

---

## Phase 4: Integration

### Step 4.1: Update CameraViewModel

**File:** `PromptCam/ViewModels/CameraViewModel.swift`

Add a new sheet case to the `SheetRoute` enum:

```swift
enum SheetRoute: Identifiable {
    case compose
    case settings
    case recordingsLibrary  // ← Add this

    var id: String {
        switch self {
        case .compose: return "compose"
        case .settings: return "settings"
        case .recordingsLibrary: return "recordingsLibrary"  // ← Add this
        }
    }
}
```

Update the `openPhotoLibrary()` method:

```swift
func openPhotoLibrary() {
    // Open custom recordings library instead of native picker
    activeSheet = .recordingsLibrary
}
```

---

### Step 4.2: Update CameraView Sheet Routing

**File:** `PromptCam/Views/CameraView.swift`

Update the `sheetContent(for:)` method:

```swift
private func sheetContent(for route: CameraViewModel.SheetRoute) -> some View {
    Group {
        switch route {
        case .compose:
            ComposeScriptSheet(
                initialText: viewModel.config.text,
                onSave: { newText in
                    viewModel.updateScriptText(newText)
                    viewModel.dismissActiveSheet()
                },
                onCancel: {
                    viewModel.dismissActiveSheet()
                }
            )
        case .settings:
            CameraSettingsSheet(
                onDismiss: { viewModel.dismissActiveSheet() }
            )
        case .recordingsLibrary:
            RecordingsLibrarySheet()  // ← Add this
        }
    }
}
```

**Remove the native PhotosPicker:** Delete or comment out these sections in CameraView.swift:

```swift
// DELETE OR COMMENT OUT:
// @State private var selectedMediaItem: PhotosPickerItem?
// .photosPicker(...)
// .onChange(of: selectedMediaItem) { ... }
// .onChange(of: viewModel.isPhotoPickerPresented) { ... }
```

Also remove `isPhotoPickerPresented` property from `CameraViewModel.swift` if it's no longer used.

---

## Phase 5: Testing Checklist

### Permissions

- [ ] Photo library permission granted
- [ ] Limited library access works correctly
- [ ] Permission denial shows appropriate message

### Loading

- [ ] Recordings load on sheet open
- [ ] Thumbnails render correctly
- [ ] Empty state shows when no recordings exist
- [ ] Loading indicator appears during fetch

### Grid Display

- [ ] 3-column grid layout displays properly
- [ ] Aspect ratios preserved
- [ ] Duration badges show correct times
- [ ] Play icons visible on all thumbnails

### Playback

- [ ] Tapping thumbnail opens player
- [ ] Video plays automatically
- [ ] Controls show/hide on tap
- [ ] Close button dismisses player
- [ ] Player cleans up on dismiss

### Sharing

- [ ] Share button appears in player
- [ ] Share sheet opens with video
- [ ] Can share to Messages, Mail, etc.
- [ ] Exported video plays correctly

### Deletion

- [ ] Delete button shows confirmation
- [ ] Deletion removes from grid
- [ ] Deletion removes from photo library
- [ ] Cancel button works

### Visual

- [ ] Custom background (Theme.bgGrad) applied
- [ ] Title bar styled correctly (.toolbarColorScheme(.dark))
- [ ] Animations smooth
- [ ] Layout works on different screen sizes

---

## Phase 6: Optional Enhancements

### 6.1: Search & Filter

Add search bar and date filters to `RecordingsLibrarySheet`:

```swift
@State private var searchText = ""
@State private var filterMode: FilterMode = .all

enum FilterMode: String, CaseIterable {
    case all = "All"
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
}
```

### 6.2: Multi-Select Mode

Add batch operations for sharing/deleting multiple recordings:

```swift
@State private var isMultiSelectMode = false
@State private var selectedRecordings: Set<Recording> = []
```

### 6.3: App-Specific Album

Create and save recordings to a "PromptCam" album:

```swift
func createAppAlbum() async -> PHAssetCollection? {
    // Create or fetch existing album
}
```

### 6.4: Export with Metadata

Add teleprompter script overlay or export metadata with video:

```swift
func exportWithMetadata(recording: Recording, script: String) async -> URL?
```

---

## Common Pitfalls

### 1. Main Actor Isolation

PHAsset queries should run on background thread, but SwiftUI updates must be on main thread:

```swift
await withCheckedContinuation { continuation in
    DispatchQueue.global(qos: .userInitiated).async {
        // PHAsset fetch here
        continuation.resume(returning: results)
    }
}
```

### 2. Thumbnail Caching

Don't reload thumbnails on every scroll. Use `LazyVGrid` and cache thumbnails in a dictionary by asset ID.

### 3. Memory Management

AVPlayer instances must be cleaned up in `.onDisappear` to prevent memory leaks:

```swift
.onDisappear {
    player?.pause()
    player = nil
}
```

### 4. Permission Timing

Always check photo library permissions before fetching assets. Return empty array if unauthorized.

### 5. ShareLink Requirements

`ShareLink` requires iOS 16+. For iOS 15 support, use `UIActivityViewController` wrapped in `UIViewControllerRepresentable`.

---

## Build & Test Commands

```bash
# Build project
xcodegen generate
xcodebuild -project PromptCam.xcodeproj -scheme PromptCam -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run tests (if you add unit tests later)
xcodebuild test -project PromptCam.xcodeproj -scheme PromptCam -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## File Summary

**New files to create (7 total):**

1. `PromptCam/Models/Recording.swift`
2. `PromptCam/Services/RecordingsService.swift`
3. `PromptCam/ViewModels/RecordingsLibraryViewModel.swift`
4. `PromptCam/Views/Recordings/RecordingThumbnailView.swift`
5. `PromptCam/Views/Recordings/RecordingPlayerView.swift`
6. `PromptCam/Views/Sheets/RecordingsLibrarySheet.swift`

**Files to modify (2 total):**

1. `PromptCam/ViewModels/CameraViewModel.swift` — Add `.recordingsLibrary` case, update `openPhotoLibrary()`
2. `PromptCam/Views/CameraView.swift` — Add sheet routing, remove native PhotosPicker

**Estimated lines of code:** ~600-700 LOC

---

## Implementation Order

1. **Day 1 (2-3 hours):** Data layer — Models, Services, ViewModel
2. **Day 2 (2-3 hours):** UI components — Thumbnail view, Grid view, Player view
3. **Day 3 (1 hour):** Integration — Wire up to CameraView, test end-to-end
4. **Day 4 (Optional):** Enhancements — Search, multi-select, albums

---

## Notes

- All file paths assume XcodeGen is being used. If manually managing Xcode project, add files to the target via Xcode UI.
- Theme constants (`Theme.bgGrad`, `Theme.space16`, etc.) already exist in `Theme.swift`.
- Photo library permission prompts are already implemented in `PermissionService.swift`.
- This guide uses modern Swift concurrency (async/await). Minimum deployment target: iOS 15.0.

---

**Ready to implement? Start with Phase 1 and work through sequentially. Each phase is independently testable.**
