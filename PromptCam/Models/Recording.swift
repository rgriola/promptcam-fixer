import AVFoundation
import Photos

/// Lightweight, Sendable view model of a video recording.
/// Does NOT store the PHAsset reference — look it up on demand by localIdentifier
/// so the model can cross actor boundaries cleanly under Swift 6 strict concurrency.
struct Recording: Identifiable, Hashable, Sendable {
    let id: String // PHAsset.localIdentifier
    let duration: TimeInterval
    let creationDate: Date
    let pixelWidth: Int
    let pixelHeight: Int

    init(asset: PHAsset) {
        id = asset.localIdentifier
        duration = asset.duration
        creationDate = asset.creationDate ?? Date()
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Fallback initialiser used when PHAsset is unavailable (Transferable path).
    /// Metadata is loaded asynchronously by the caller before calling this init.
    init(fallbackIdentifier: String, duration: TimeInterval = 0, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        id = fallbackIdentifier
        self.duration = duration
        creationDate = Date()
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}
