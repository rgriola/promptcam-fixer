import AVFoundation
import Photos
import UIKit

/// Fetches and manages video recordings stored in the photo library.
struct RecordingsService: Sendable {

    /// Shared caching image manager for grid thumbnails.
    static let cachingManager = PHCachingImageManager()

    /// Serial queue for pre-warm work. `PHAsset.fetchAssets(withLocalIdentifiers:)`
    /// is synchronous and takes several ms per call; running it on main pegs
    /// the UI thread during rapid carousel swipes (Time Profiler measured
    /// 7ms/78% per sample on iPhone 13). PHCachingImageManager is thread-safe.
    private static let cachingQueue = DispatchQueue(
        label: "com.rgriola.promptcam.recordings.caching",
        qos: .userInitiated
    )

    nonisolated(unsafe) private static let assetCache = NSCache<NSString, PHAsset>()

    /// Maximum videos loaded into the carousel. Tune during testing.
    static let carouselFetchLimit = 15

    /// Fetches videos from the user's library, newest first.
    func fetchAllRecordings() async -> [Recording] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            Log.recordings.info("Photo library not authorized (\(status.rawValue, privacy: .public))")
            return []
        }

        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = Self.carouselFetchLimit

            // mediaType: .video already excludes photos and Live Photo images.
            let fetch = PHAsset.fetchAssets(with: .video, options: options)
            var out: [Recording] = []
            out.reserveCapacity(fetch.count)
            fetch.enumerateObjects { asset, _, _ in out.append(Recording(asset: asset)) }
            return out
        }.value
    }

    /// Thumbnail for the most recently saved video — used by the camera-roll
    /// button on the footer to mirror the iOS Camera app's thumbnail preview.
    /// Returns `nil` when the library is empty, not authorized, or the fetch fails.
    ///
    /// Uses `.opportunistic` delivery so iCloud-offloaded videos return a
    /// degraded local thumbnail immediately (if cached), then the full image
    /// when the download completes. Matches the pattern used by the carousel.
    func latestVideoThumbnail(targetSize: CGSize) async -> UIImage? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        guard let asset = PHAsset.fetchAssets(with: .video, options: options).firstObject else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let imgOptions = PHImageRequestOptions()
            // .fastFormat = single callback, single decode. Half the CPU of
            // .opportunistic which fires degraded + full for every iCloud asset.
            // For iCloud-offloaded assets fastFormat may return nil; the caller
            // (CarouselCell) has a bounded retry loop that handles that path.
            imgOptions.deliveryMode = .fastFormat
            imgOptions.isNetworkAccessAllowed = true
            imgOptions.version = .current

            Self.cachingManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: imgOptions
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }


    /// Resolves a recording id back to its underlying `PHAsset`.
    private func asset(for id: String) -> PHAsset? {
        if let cached = Self.assetCache.object(forKey: id as NSString) { return cached }
        if let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
            Self.assetCache.setObject(fetched, forKey: id as NSString)
            return fetched
        }
        return nil
    }

    static func imageRequestOptions(deliveryMode: PHImageRequestOptionsDeliveryMode = .fastFormat) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = deliveryMode
        options.isNetworkAccessAllowed = true
        options.version = .current
        return options
    }

    /// Thumbnail via the shared caching manager.
    ///
    /// Delivery mode is parameterized (Phase 2) so callers can pick the
    /// right speed / CPU / iCloud-download tradeoff:
    ///
    /// - `.fastFormat` (default): single callback, single decode, cheapest.
    ///   Does NOT trigger iCloud download — returns nil for offloaded
    ///   assets with no local rep. Used by pre-warm and background paths.
    /// - `.opportunistic`: fires the callback up to twice (degraded + full)
    ///   AND triggers an iCloud download when the local rep is missing.
    ///   Used by the visible carousel cell so iCloud-offloaded thumbnails
    ///   render immediately (or start downloading) instead of returning nil
    ///   and waiting for CarouselCell's 3s retry.
    ///
    /// For `.opportunistic`, the continuation is resumed on the FIRST
    /// non-nil image (degraded or full) via a `resumed` guard — PhotoKit
    /// still fires the second callback but we discard it. At 144×144 the
    /// visible upgrade from degraded to full is imperceptible, so the extra
    /// Swift-side @State assignment isn't worth an AsyncStream refactor.
    func thumbnail(
        for recording: Recording,
        targetSize: CGSize,
        deliveryMode: PHImageRequestOptionsDeliveryMode = .fastFormat
    ) async -> UIImage? {
        guard let asset = asset(for: recording.id) else { return nil }
        return await withCheckedContinuation { continuation in
            let options = Self.imageRequestOptions(deliveryMode: deliveryMode)

            // Guard against .opportunistic firing the callback twice.
            // withCheckedContinuation crashes if resumed more than once.
            nonisolated(unsafe) var resumed = false
            Self.cachingManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let image {
                    // First non-nil image wins.
                    resumed = true
                    continuation.resume(returning: image)
                } else if !isDegraded {
                    // Final callback with no image — asset truly unavailable.
                    // For .opportunistic, a degraded==true callback with nil
                    // image just means "no local rep" and the hi-res is
                    // still downloading; wait for the next fire.
                    resumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Pre-warm thumbnails for visible cells. Runs the PhotoKit fetch and
    /// caching-start on a background queue to keep the main thread free
    /// during rapid carousel navigation.
    func startCaching(ids: [String], targetSize: CGSize, deliveryMode: PHImageRequestOptionsDeliveryMode = .fastFormat) {
        Self.cachingQueue.async {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var assets: [PHAsset] = []
            fetch.enumerateObjects { a, _, _ in assets.append(a) }
            Self.cachingManager.startCachingImages(
                for: assets, targetSize: targetSize, contentMode: .aspectFill, options: Self.imageRequestOptions(deliveryMode: deliveryMode))
        }
    }

    func stopCachingAll() {
        Self.cachingQueue.async {
            Self.cachingManager.stopCachingImagesForAllAssets()
        }
    }

    /// Resolves a `Recording` to a playable `AVURLAsset` URL using the
    /// high-quality PHImageManager path. Used by the direct player to get a
    /// URL without going through the PhotosPicker Transferable copy path,
    /// which requires downloading the full file.
    ///
    /// Returns nil if the asset is unavailable or the URL cannot be resolved.
    func resolveURL(for recording: Recording) async -> URL? {
        await resolveURL(for: recording, progress: nil).url
    }

    /// Resolves a recording's playable URL with optional progress reporting
    /// for iCloud downloads. The returned `requestID` can be passed to
    /// `PHImageManager.default().cancelImageRequest(_:)` to abort an in-flight
    /// download (e.g. when the user closes the player before the video finishes
    /// downloading from iCloud).
    ///
    /// - Parameters:
    ///   - recording: The recording to resolve.
    ///   - progress: Optional handler called on the main actor with a 0.0–1.0
    ///     download progress value. Fires ONLY when PhotoKit needs to download
    ///     the asset from iCloud; local videos resolve immediately with no
    ///     progress callbacks.
    ///   - onStart: Optional handler called synchronously with the request ID
    ///     as soon as PhotoKit begins the request. Use this to store the ID
    ///     so the request can be cancelled mid-flight (e.g. on player dismiss
    ///     or a timeout). Fires before `progress` and before the return tuple.
    /// - Returns: A tuple of (url, requestID). Either can be nil.
    func resolveURL(
        for recording: Recording,
        progress: (@MainActor @Sendable (Double) -> Void)?,
        onStart: (@Sendable (PHImageRequestID) -> Void)? = nil
    ) async -> (url: URL?, requestID: PHImageRequestID?) {
        guard let asset = asset(for: recording.id) else { return (nil, nil) }

        // Capture the progress handler as a local @Sendable so it can escape
        // into PHVideoRequestOptions.progressHandler (which is called on an
        // arbitrary queue).
        let onProgress = progress

        // Use a mutable holder so we can capture the request ID synchronously
        // from requestAVAsset's return value.
        nonisolated(unsafe) var capturedRequestID: PHImageRequestID?

        let url = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            var resumed = false
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            // .automatic (Phase 3): Apple picks the best-quality-that-loads-
            // fastest based on current network conditions. On fast Wi-Fi this
            // typically behaves like .highQualityFormat; on cellular or slow
            // links PhotoKit may return a smaller proxy so playback starts
            // sooner. Was .highQualityFormat, which always blocked until the
            // full-res original had been downloaded from iCloud (minutes for
            // a 200MB 4K clip). If video quality noticeably degrades, revert
            // to `.highQualityFormat` here or expose a per-call parameter.
            options.deliveryMode = .automatic
            if let onProgress {
                // Throttle: PhotoKit can fire progressHandler ~10 Hz per download.
                // Each callback spawns a Task { @MainActor in ... } which is
                // measurable CPU noise. Only forward when the value moves by
                // ≥0.5% (or crosses one of the guaranteed milestones), so
                // quick 50MB iCloud downloads that skip past a 1% delta still
                // show at least a few progress updates instead of silently
                // jumping from 0% straight to 100%.
                let lastReported = ThrottledDouble()
                options.progressHandler = { fraction, _, _, _ in
                    guard lastReported.shouldReport(
                        fraction,
                        minDelta: 0.005,
                        milestones: [0.25, 0.5, 0.75]
                    ) else { return }
                    // PhotoKit fires this on an arbitrary queue. Hop to main.
                    Task { @MainActor in
                        onProgress(fraction)
                    }
                }
            }
            let id = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
            capturedRequestID = id
            // Notify the caller synchronously so it can store the ID for
            // mid-flight cancellation before awaiting the continuation.
            onStart?(id)
        }

        return (url, capturedRequestID)
    }

    /// Cancels an in-flight iCloud download started by `resolveURL(for:progress:)`.
    /// Safe to call with a nil ID or after the request has already completed.
    func cancelResolveURL(requestID: PHImageRequestID?) {
        guard let requestID else { return }
        PHImageManager.default().cancelImageRequest(requestID)
    }

    /// Fetches the most recent video recording, or nil if the library is empty.
    func fetchLatestRecording() async -> Recording? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        
        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 1
            if let asset = PHAsset.fetchAssets(with: .video, options: options).firstObject {
                return Recording(asset: asset)
            }
            return nil
        }.value
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
        // PHAsset.localIdentifier contains '/' which is invalid in path components;
        // sanitize to keep filenames stable and unique across runs.
        let safeId = recording.id.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueVue-\(safeId).\(ext)")

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

// MARK: - Throttle Helper

/// Small thread-safe helper for throttling repeated numeric callbacks.
/// Reports when the new value moves by at least `minDelta` from the last
/// reported value, when it crosses the 0.0 / 1.0 boundary, or when it
/// crosses one of the caller-supplied milestones for the first time. Used
/// to keep PhotoKit's high-frequency progressHandler from spawning a Task
/// on every tick while still guaranteeing meaningful updates on quick
/// downloads that would otherwise skip past the delta threshold.
private final class ThrottledDouble: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Double? = nil
    private var reportedMilestones: Set<Double> = []

    /// - Parameters:
    ///   - value: The candidate value in [0, 1].
    ///   - minDelta: Minimum absolute change since the last reported value.
    ///   - milestones: Values (0–1) that should always fire the first time
    ///     they're reached, regardless of delta. Empty by default.
    func shouldReport(
        _ value: Double,
        minDelta: Double,
        milestones: [Double] = []
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // Always report boundary values so callers see the true start/end.
        if value <= 0.0 || value >= 1.0 {
            last = value
            return true
        }
        // First crossing of a milestone always fires so quick downloads have
        // at least a few visible updates even below the delta threshold.
        for milestone in milestones where value >= milestone && !reportedMilestones.contains(milestone) {
            reportedMilestones.insert(milestone)
            last = value
            return true
        }
        if let last, abs(value - last) < minDelta {
            return false
        }
        last = value
        return true
    }
}
