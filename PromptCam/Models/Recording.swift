import Photos

/// Lightweight, Sendable view model of a video recording.
/// Does NOT store the PHAsset reference — look it up on demand by localIdentifier
/// so the model can cross actor boundaries cleanly under Swift 6 strict concurrency.
struct Recording: Identifiable, Hashable, Sendable {
    let id: String          // PHAsset.localIdentifier
    let duration: TimeInterval
    let creationDate: Date
    let pixelWidth: Int
    let pixelHeight: Int

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.duration = asset.duration
        self.creationDate = asset.creationDate ?? Date()
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
