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
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Thumbnail via the shared caching manager.
    ///
    /// Uses `.fastFormat` delivery — single callback, single decode. For
    /// iCloud-offloaded assets this may return nil (no local fast rep). The
    /// caller (CarouselCell) has a bounded 2-retry loop that catches those
    /// cases; after both retries fail the cell shows a permanent placeholder.
    ///
    /// Previously used `.opportunistic` which fires the callback twice
    /// (degraded + full) and forces two decodes per iCloud asset. Measured on
    /// iPhone 13 that doubled CPU during carousel scrolling.
    func thumbnail(for recording: Recording, targetSize: CGSize) async -> UIImage? {
        guard let asset = asset(for: recording.id) else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = true    // pull from iCloud in the background if needed
            options.version = .current

            Self.cachingManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Pre-warm thumbnails for visible cells. Runs the PhotoKit fetch and
    /// caching-start on a background queue to keep the main thread free
    /// during rapid carousel navigation.
    func startCaching(ids: [String], targetSize: CGSize) {
        Self.cachingQueue.async {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var assets: [PHAsset] = []
            fetch.enumerateObjects { a, _, _ in assets.append(a) }
            Self.cachingManager.startCachingImages(
                for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
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
    /// - Returns: A tuple of (url, requestID). Either can be nil.
    func resolveURL(
        for recording: Recording,
        progress: (@MainActor @Sendable (Double) -> Void)?
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
            options.deliveryMode = .highQualityFormat
            if let onProgress {
                // Throttle: PhotoKit can fire progressHandler ~10 Hz per download.
                // Each callback spawns a Task { @MainActor in ... } which is
                // measurable CPU noise. Only forward when the value moves by ≥1%
                // (or is a definitive 0.0 / 1.0 milestone).
                let lastReported = ThrottledDouble()
                options.progressHandler = { fraction, _, _, _ in
                    guard lastReported.shouldReport(fraction, minDelta: 0.01) else { return }
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
    func fetchLatestRecording() -> Recording? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .video, options: options).firstObject else {
            return nil
        }
        return Recording(asset: asset)
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
            .appendingPathComponent("PromptCam-\(safeId).\(ext)")

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
/// reported value, or when it crosses the 0.0 / 1.0 boundary. Used to keep
/// PhotoKit's high-frequency progressHandler from spawning a Task on every
/// tick.
private final class ThrottledDouble: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Double? = nil

    func shouldReport(_ value: Double, minDelta: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // Always report boundary values so callers see the true start/end.
        if value <= 0.0 || value >= 1.0 {
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
