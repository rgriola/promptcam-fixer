import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct RecordingPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let recording: Recording
    let videoURL: URL?
    let onDelete: () -> Void

    @State private var player: AVPlayer?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if let videoURL {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .task(id: videoURL) {
                        player?.pause()
                        let p = AVPlayer(url: videoURL)
                        player = p
                        p.play()
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
            } else {
                VStack(spacing: Theme.space16) {
                    ProgressView().tint(Theme.primaryText)
                    Text("Loading video…")
                        .font(Theme.font16Regular)
                        .foregroundStyle(Theme.primaryText)
                }
            }

            HStack(spacing: Theme.space16) {
                Button { dismiss() } label: {
                    controlIcon("xmark.circle.fill", tint: Theme.primaryText)
                }
                Spacer()
                shareButton
                Button { showDeleteConfirmation = true } label: {
                    controlIcon("trash.circle.fill", tint: Theme.red)
                }
            }
            .padding(.horizontal, Theme.space16)
            .padding(.top, Theme.space8)
        }
        .confirmationDialog(
            "Delete Recording",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recording will be permanently deleted from your photo library.")
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let videoURL {
            ShareLink(
                item: VideoFile(url: videoURL),
                preview: SharePreview(recording.formattedDuration)
            ) {
                controlIcon("square.and.arrow.up.circle.fill", tint: Theme.primaryText)
            }
        } else {
            controlIcon("square.and.arrow.up.circle.fill", tint: Theme.secondaryText)
        }
    }

    private func controlIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 32))
            .foregroundStyle(tint)
            .shadow(color: .black.opacity(0.3), radius: 4)
    }
}

/// Transferable wrapper for sharing video files via ShareLink.
/// Wraps a URL so the native share sheet attaches the actual file
/// instead of sharing a URL string.
struct VideoFile: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            contentType: .movie,
            shouldAttemptToOpenInPlace: false,
            exporting: { video in
                SentTransferredFile(video.url)
            },
            importing: { received in
                // Not supported — this type is export-only for sharing
                throw CocoaError(.fileReadUnknown)
            }
        )
    }
}
