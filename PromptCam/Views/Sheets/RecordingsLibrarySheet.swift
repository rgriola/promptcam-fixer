import AVFoundation
import Photos
import PhotosUI
import SwiftUI

struct RecordingsLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedRecording: Recording?
    @State private var videoURL: URL?

    var body: some View {
        NavigationStack {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 1,
                selectionBehavior: .default,
                matching: .videos
            ) {
                EmptyView()
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .tint(Theme.green)
            .navigationTitle("Camera Roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseToolbarButton { dismiss() }
                }
            }
            .onChange(of: selectedItems) { _, items in
                guard let item = items.first else { return }
                Task { await openPlayer(for: item) }
            }
        }
        .fullScreenCover(item: $selectedRecording, onDismiss: resetSelection) { recording in
            RecordingPlayerView(
                recording: recording,
                videoURL: videoURL,
                onDelete: {
                    Task { await deleteRecording(recording) }
                }
            )
        }
        // Step 2 (fast path only): URL resolves after player is open
        .onChange(of: selectedRecording) { _, newRecording in
            guard newRecording != nil, videoURL == nil,
                  let identifier = selectedItems.first?.itemIdentifier else { return }
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            guard let asset = result.firstObject else { return }
            Task { videoURL = await resolveVideoURL(phAsset: asset) }
        }
    }

    // MARK: - Open Player

    /// Tries the PHAsset fast path first; falls back to Transferable file copy
    /// so that the player always opens regardless of library access level or
    /// whether itemIdentifier is available.
    @MainActor
    private func openPlayer(for item: PhotosPickerItem) async {
        videoURL = nil

        // ── Fast path: PHAsset ──────────────────────────────────────────────
        if let identifier = item.itemIdentifier,
           let asset = PHAsset.fetchAssets(
               withLocalIdentifiers: [identifier], options: nil
           ).firstObject
        {
            // Present the player immediately; URL loads via onChange(of: selectedRecording)
            selectedRecording = Recording(asset: asset)
            return
        }

        // ── Fallback: Transferable (copies file — works without PHAsset access) ──
        if let movie = try? await item.loadTransferable(type: RecordingsMovieTransferable.self) {
            let identifier = item.itemIdentifier ?? UUID().uuidString
            let av = AVURLAsset(url: movie.url)
            // Load metadata using non-deprecated async APIs
            let cmDuration = (try? await av.load(.duration)) ?? .zero
            let durationSecs = CMTimeGetSeconds(cmDuration)
            let tracks = (try? await av.loadTracks(withMediaType: .video)) ?? []
            let naturalSize = (try? await tracks.first?.load(.naturalSize)) ?? .zero
            videoURL = movie.url
            selectedRecording = Recording(
                fallbackIdentifier: identifier,
                duration: durationSecs.isNaN || durationSecs.isInfinite ? 0 : durationSecs,
                pixelWidth: Int(naturalSize.width),
                pixelHeight: Int(naturalSize.height)
            )
        }
    }

    // MARK: - URL Resolution (fast path step 2)

    private func resolveVideoURL(phAsset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true   // stream from iCloud if needed
            options.version = .current
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
    }

    // MARK: - Delete / Reset

    /// Clears picker selection on player dismiss so the same video can be tapped again immediately.
    private func resetSelection() {
        selectedItems = []
        videoURL = nil
    }

    private func deleteRecording(_ recording: Recording) async {
        // Delegate to the nonisolated RecordingsService — inlining
        // PHPhotoLibrary.performChanges from this @MainActor View method taints
        // the change closure with MainActor isolation and crashes under Swift
        // 6's executor check when PhotoKit dispatches it onto its own serial
        // queue. See CameraView.onDelete for the matching fix.
        _ = await RecordingsService().deleteRecording(recording)
        selectedRecording = nil
        selectedItems = []
        videoURL = nil
    }
}

// MARK: - Transferable

/// Copies a video from the photo library into a temp file.
/// Used as fallback when PHAsset lookup fails (limited access or nil itemIdentifier).
private struct RecordingsMovieTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let name = received.file.lastPathComponent
            let subdir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
            let dest = subdir.appendingPathComponent(name)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}
