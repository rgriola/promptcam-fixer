// July 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Testable seam for saving videos to Photos
// Small protocol so tests can inject a fake saver without touching PHPhotoLibrary.

import Foundation
import Photos

/// Saves a video file to the user's Photo Library. Small seam so unit tests
/// can substitute a fake implementation without depending on PhotoKit.
protocol PhotoLibrarySaver: Sendable {
    /// Saves the video at `url` to the Photo Library.
    /// - Throws: A saver-specific error if the save fails.
    func saveVideo(at url: URL) async throws
}

/// Production implementation backed by `PHPhotoLibrary.shared()`.
struct DefaultPhotoLibrarySaver: PhotoLibrarySaver {
    func saveVideo(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: PhotoLibrarySaverError.saveDidNotComplete)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }
}

enum PhotoLibrarySaverError: Error {
    case saveDidNotComplete
}
