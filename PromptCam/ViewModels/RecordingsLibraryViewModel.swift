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

    /// Number of thumbnails to pre-warm (roughly one screenful of 3-column grid).
    private static let prefetchThumbnailCount = 18
    private static let thumbnailSize = CGSize(width: 300, height: 300)

    var hasAccess: Bool {
        let status = permissions.photoLibraryStatus
        return status == .authorized || status == .limited
    }

    /// Pre-fetches recordings and pre-warms thumbnails in the background.
    /// Called from CameraViewModel.onAppear so data is ready when the sheet opens.
    func prefetch() async {
        guard hasAccess, recordings.isEmpty else { return }
        recordings = await service.fetchAllRecordings()
        Log.recordings.info("Prefetched \(self.recordings.count, privacy: .public) recordings")

        // Pre-warm the first screenful of thumbnails via PHCachingImageManager.
        let prefetchIds = Array(recordings.prefix(Self.prefetchThumbnailCount).map(\.id))
        if !prefetchIds.isEmpty {
            service.startCaching(ids: prefetchIds, targetSize: Self.thumbnailSize)
        }
    }

    /// Loads recordings for display. Skips fetch if already pre-populated.
    func load() async {
        guard hasAccess else {
            recordings = []
            return
        }

        if recordings.isEmpty {
            isLoading = true
            defer { isLoading = false }
            recordings = await service.fetchAllRecordings()
            Log.recordings.info("Loaded \(self.recordings.count, privacy: .public) recordings")
        }
    }

    /// Forces a fresh re-fetch of all recordings. Called after a new video
    /// is saved to the photo library so the Camera Roll stays current.
    func refresh() async {
        guard hasAccess else { return }
        recordings = await service.fetchAllRecordings()
        Log.recordings.info("Refreshed \(self.recordings.count, privacy: .public) recordings")
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
