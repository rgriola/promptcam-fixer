import Photos
import SwiftUI

struct RecordingsLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RecordingsLibraryViewModel()

    // UI state — NSCache auto-evicts under memory pressure, preventing unbounded growth.
    @State private var thumbnailCache = NSCache<NSString, UIImage>()
    @State private var selectedRecording: Recording?
    @State private var videoURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgGrad.ignoresSafeArea()

                if !viewModel.hasAccess {
                    permissionDeniedView
                } else if viewModel.isLoading {
                    ProgressView().tint(Theme.primaryText)
                } else if viewModel.recordings.isEmpty {
                    emptyStateView
                } else {
                    recordingsGrid
                }
            }
            .navigationTitle("Camera Roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseToolbarButton { dismiss() }
                }
            }
            .task { await viewModel.load() }
            .fullScreenCover(item: $selectedRecording) { recording in
                RecordingPlayerView(
                    recording: recording,
                    videoURL: videoURL,
                    onDelete: { Task { await viewModel.delete(recording) } }
                )
            }
            .task(id: selectedRecording) {
                videoURL = nil
                guard let rec = selectedRecording else { return }
                videoURL = await viewModel.exportForSharing(rec)
            }
        }
        .onDisappear {
            viewModel.stopCaching()
        }
    }

    private var recordingsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 1),
                    GridItem(.flexible(), spacing: 1),
                    GridItem(.flexible(), spacing: 1)
                ],
                spacing: 1
            ) {
                ForEach(viewModel.recordings) { recording in
                    RecordingThumbnailView(
                        recording: recording,
                        thumbnail: thumbnailCache.object(forKey: recording.id as NSString)
                    ) {
                        selectedRecording = recording
                    }
                    .task(id: recording.id) {
                        let key = recording.id as NSString
                        guard thumbnailCache.object(forKey: key) == nil else { return }
                        let size = CGSize(width: 300, height: 300)
                        if let img = await viewModel.thumbnail(for: recording, size: size) {
                            thumbnailCache.setObject(img, forKey: key)
                        }
                    }
                    .onAppear {
                        let size = CGSize(width: 300, height: 300)
                        if let idx = viewModel.recordings.firstIndex(of: recording) {
                            let start = max(0, idx - 10)
                            let end = min(viewModel.recordings.count, idx + 10)
                            let ids = viewModel.recordings[start..<end].map(\.id)
                            viewModel.startCaching(ids: ids, size: size)
                        }
                    }
                }
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: Theme.space16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Theme.secondaryText)
            Text("Photo Library Access Required")
                .font(Theme.font20Semibold)
                .foregroundStyle(Theme.primaryText)
            Text("Grant PromptCam permission to read your videos in Settings.")
                .font(Theme.font16Regular)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .padding(.horizontal, Theme.space32)
            .padding(.vertical, Theme.space8)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
            .foregroundStyle(Theme.blackText)
            .font(Theme.font16Semibold)
        }
        .padding(Theme.space32)
    }

    private var emptyStateView: some View {
        VStack(spacing: Theme.space16) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundStyle(Theme.secondaryText)
            Text("No Videos Found")
                .font(Theme.font20Semibold)
                .foregroundStyle(Theme.primaryText)
            Text("Record a video to see it here.")
                .font(Theme.font16Regular)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
