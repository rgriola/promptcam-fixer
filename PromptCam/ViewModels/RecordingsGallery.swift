// July 17, 2026 - GitHub Copilot - Extracted direct player / recordings carousel from CameraViewModel
// July 18, 2026 - GitHub Copilot (Claude Opus 4.7) - async refresh + atomic delete(_:) so callers
//     can await the post-delete state transition. Prevents SwiftUI View-identity race that
//     crashed under Swift 6 concurrency when fullScreenCover reevaluated mid-teardown.
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
    ///
    /// Awaitable so callers can chain post-refresh work (e.g. presenting the
    /// player) without racing the underlying `prefetch`. The fire-and-forget
    /// variant lives in `refreshInBackground()` for save-completion paths
    /// that don't need to sequence UI transitions.
    func refresh() async {
        await prefetch()
    }

    /// Non-awaited refresh for save-completion paths that should not block
    /// the caller. Delete flows should use `refresh()` (awaitable) instead
    /// so state transitions are deterministic.
    func refreshInBackground() {
        Task { await prefetch() }
    }

    /// Atomic delete: removes the recording from Photo Library, then updates
    /// all @Observable properties in a single main-actor transaction so any
    /// downstream `.onChange` / `.fullScreenCover` re-evaluation sees one
    /// consistent snapshot.
    ///
    /// Returns `true` if the underlying PhotoKit delete succeeded. On success,
    /// `latestRecording` is set to the **first** remaining recording (the
    /// most recent). `latestVideoURL` is cleared for lazy resolve, and
    /// `recentRecordings` is refreshed to the full library.
    ///
    /// Reset-to-top (rather than index-preserving) is deliberate: users
    /// expect the library to snap back to the front after a delete, and it
    /// keeps the parent (`latestRecording`) in agreement with the player
    /// (`activeRecording = newRecordings.first`) so the carousel and player
    /// converge on the same active clip after the delete cascade.
    ///
    /// If the library becomes empty, `latestRecording` becomes nil — callers
    /// (e.g. `CameraView`'s delete handler) should observe that and dismiss
    /// the player.
    @discardableResult
    func delete(_ recording: Recording) async -> Bool {
        let ok = await recordingsService.deleteRecording(recording)
        guard ok else { return false }

        let all = await recordingsService.fetchAllRecordings()

        // Single main-actor transaction — @Observable coalesces these writes.
        recentRecordings = all
        latestRecording = all.first
        latestVideoURL = nil    // resolve lazily in the player for the new recording

        return true
    }
}

