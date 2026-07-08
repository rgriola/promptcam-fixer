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
            imgOptions.deliveryMode = .opportunistic
            imgOptions.isNetworkAccessAllowed = true
            imgOptions.version = .current

            var resumed = false
            Self.cachingManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: imgOptions
            ) { image, info in
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true

                if let image {
                    resumed = true
                    continuation.resume(returning: image)
                } else if !isDegraded {
                    resumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }


    /// Resolves a recording id back to its underlying `PHAsset`.
    private func asset(for id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Thumbnail via the shared caching manager.
    ///
    /// Uses `.opportunistic` delivery so PhotoKit returns a degraded local
    /// thumbnail immediately, then calls back a second time with full quality
    /// once the asset downloads from iCloud (if needed). Resumes on the FIRST
    /// non-nil result — continuations are one-shot, so we cannot wait for the
    /// upgraded image. The first callback is usually the degraded one; that's
    /// fine for carousel cells (visually indistinguishable at 84pt).
    ///
    /// Falls back to nil only when both callbacks return no image.
    func thumbnail(for recording: Recording, targetSize: CGSize) async -> UIImage? {
        guard let asset = asset(for: recording.id) else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true    // pull from iCloud if local copy absent
            options.version = .current

            var resumed = false
            Self.cachingManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Continuation is one-shot: only the FIRST callback (of the 2
                // opportunistic ones) is allowed to resume it.
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true

                if let image {
                    // Take the first image we get — degraded is better than nil.
                    resumed = true
                    continuation.resume(returning: image)
                } else if !isDegraded {
                    // Final callback (isDegraded=false) with no image means
                    // nothing is available at all. Resume with nil.
                    resumed = true
                    continuation.resume(returning: nil)
                }
                // If image==nil AND isDegraded==true, this was the initial
                // no-local-cache callback — wait for the full-quality one.
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
                options.progressHandler = { fraction, _, _, _ in
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
