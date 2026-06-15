import Photos
import SwiftUI

@MainActor
@Observable
final class RecordingsLibraryViewModel {
    private(set) var recordings: [Recording] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let service = RecordingsService()
    private let permissions = PermissionService()

    var hasAccess: Bool {
        let status = permissions.photoLibraryStatus
        return status == .authorized || status == .limited
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        guard hasAccess else {
            recordings = []
            return
        }

        recordings = await service.fetchAllRecordings()
        Log.recordings.info("Loaded \(self.recordings.count, privacy: .public) recordings")
    }

    func thumbnail(for r: Recording, size: CGSize) async -> UIImage? {
        await service.thumbnail(for: r, targetSize: size)
    }

    func exportForSharing(_ r: Recording) async -> URL? {
        await service.exportForSharing(r)
    }

    func startCaching(ids: [String], size: CGSize) {
        service.startCaching(ids: ids, targetSize: size)
    }

    func stopCaching() {
        service.stopCachingAll()
    }

    func delete(_ recording: Recording) async {
        let ok = await service.deleteRecording(recording)
        if ok {
            recordings.removeAll { $0.id == recording.id }
        } else {
            errorMessage = "Failed to delete recording"
        }
    }
}
