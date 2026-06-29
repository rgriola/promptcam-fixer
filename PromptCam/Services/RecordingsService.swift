import AVFoundation
import Photos
import UIKit

/// Fetches and manages video recordings stored in the photo library.
struct RecordingsService: Sendable {

    /// Shared caching image manager for grid thumbnails.
    static let cachingManager = PHCachingImageManager()

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

    /// Thumbnail via the shared caching manager. Uses `.fastFormat` delivery
    /// for responsive grid scrolling — returns a single callback (safe for
    /// continuations) with a quick low-res decode. For a 300×300 grid cell,
    /// the fast decode is visually indistinguishable from high-quality.
    func thumbnail(for recording: Recording, targetSize: CGSize) async -> UIImage? {
        guard let asset = asset(for: recording.id) else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = true
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
