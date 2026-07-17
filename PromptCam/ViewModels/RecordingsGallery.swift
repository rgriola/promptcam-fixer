// July 17, 2026 - GitHub Copilot - Extracted direct player / recordings carousel from CameraViewModel
import CoreGraphics
import Foundation

/// Owns the recordings carousel and direct-player state for the camera screen.
/// Extracted from `CameraViewModel` so the coordinator stays thin.
///
/// Pre-fetches the latest recording (and its resolved URL) so the direct player
/// opens without delay, and pre-warms carousel thumbnails via
/// `PHCachingImageManager`.
///
/// **@MainActor**: all observable properties drive SwiftUI views.
@MainActor
@Observable
final class RecordingsGallery {
    /// The most recently recorded video, pre-fetched so the player opens immediately.
    var latestRecording: Recording?
    /// Resolved URL for `latestRecording` — ready before the player opens.
    var latestVideoURL: URL?
    /// First 8 recordings for the carousel, pre-warmed by PHCachingImageManager.
    var recentRecordings: [Recording] = []
    /// Controls direct player sheet presentation.
    var showDirectPlayer = false

    @ObservationIgnored private let recordingsService = RecordingsService()

    /// Fetches the latest recording and pre-resolves its URL so the player
    /// opens without delay. Loads ALL recordings for the carousel — Recording
    /// objects are lightweight PHAsset wrappers (~100 bytes each). Only the
    /// first window of thumbnails is pre-warmed; the rest load on demand as
    /// the user swipes.
    func prefetch() async {
        let latest = recordingsService.fetchLatestRecording()
        latestRecording = latest

        // Resolve URL in background so it's ready when player opens.
        if let latest {
            latestVideoURL = await recordingsService.resolveURL(for: latest)
        }

        // Fetch all recordings — no limit. PHAsset references are tiny.
        let all = await recordingsService.fetchAllRecordings()
        recentRecordings = all

        // Pre-warm thumbnails for the first visible window only.
        let warmIDs = all.prefix(8).map(\.id)
        if !warmIDs.isEmpty {
            let carouselSize = CGSize(width: 144, height: 144)
            recordingsService.startCaching(ids: Array(warmIDs), targetSize: carouselSize)
        }
    }

    /// Pre-warms carousel thumbnails in a sliding window around the given
    /// recording. Call this when the user navigates to a new item so adjacent
    /// thumbnails are ready before they scroll into view.
    ///
    /// Window default expanded from ±4 to ±6 (Phase 2) so a full flick to a
    /// far-away cell doesn't outrun the pre-warm on older devices (A11/A12)
    /// where thumbnail decode is 60–100ms per cell.
    func warmCarousel(around recording: Recording, windowSize: Int = 6) {
        guard let index = recentRecordings.firstIndex(where: { $0.id == recording.id }) else { return }
        let lo = max(0, index - windowSize)
        let hi = min(recentRecordings.count - 1, index + windowSize)
        let ids = recentRecordings[lo...hi].map(\.id)
        recordingsService.startCaching(ids: ids, targetSize: CGSize(width: 144, height: 144))
    }

    /// Call after a recording finishes saving to refresh the player state.
    func refresh() {
        Task { await prefetch() }
    }
}
