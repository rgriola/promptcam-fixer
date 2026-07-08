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
            imgOptions.deliveryMode = .fastFormat  // single callback, safe for continuation
            imgOptions.isNetworkAccessAllowed = true
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
    /// Uses `.opportunistic` delivery so PhotoKit returns a degraded local
    /// thumbnail immediately, then calls back a second time with full quality
    /// once the asset downloads from iCloud (if needed). The continuation
    /// resolves on the FIRST non-nil result so the cell shows something fast;
    /// callers that need the final quality should use `thumbnailHighQuality`.
    ///
    /// Falls back to a generic placeholder (nil) only when no representation
    /// at all is available locally or remotely — e.g. a corrupted PHAsset.
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
                // .opportunistic can fire twice: once with a degraded local copy,
                // then again with the full iCloud-fetched image. Resume on the
                // first non-nil result so the cell shows something immediately.
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if let image {
                    // Accept degraded thumbnails immediately — better than blank.
                    // If this is degraded, PhotoKit will fire again with the full
                    // version; the cell's `.task(id:)` rebind will update it then.
                    if !isDegraded {
                        resumed = true
                    }
                    continuation.resume(returning: image)
                } else if isDegraded == false {
                    // Final callback with nil = no image available at all.
                    resumed = true
                    continuation.resume(returning: nil)
                }
                // If degraded == true and image == nil, PhotoKit is still fetching.
                // Wait for the next callback.
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
        guard let asset = asset(for: recording.id) else { return nil }
        return await withCheckedContinuation { continuation in
            var resumed = false
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
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
