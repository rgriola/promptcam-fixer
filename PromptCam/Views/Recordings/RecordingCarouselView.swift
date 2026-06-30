// PromptCam — Recording Carousel
// Horizontal strip of video thumbnails shown below the player timeline.
// Pre-warmed thumbnails mean cells render instantly without visible loading.
import Photos
import SwiftUI

/// A horizontal strip of video thumbnails for quick access to recent recordings.
/// Selecting a thumbnail calls `onSelect` so the parent player can swap the video
/// without dismissing and reopening the sheet.
struct RecordingCarouselView: View {

    let recordings: [Recording]
    let activeRecordingID: String
    let thumbnailLoader: (Recording) async -> UIImage?
    let onSelect: (Recording) -> Void

    private let cellSize: CGFloat = 72

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.space8) {
                ForEach(recordings) { recording in
                    CarouselCell(
                        recording: recording,
                        isActive: recording.id == activeRecordingID,
                        cellSize: cellSize,
                        thumbnailLoader: thumbnailLoader
                    )
                    .onTapGesture { onSelect(recording) }
                }
            }
            .padding(.horizontal, Theme.space16)
            .padding(.vertical, Theme.space8)
        }
        .frame(height: cellSize + Theme.space16 * 2)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Carousel Cell

private struct CarouselCell: View {
    let recording: Recording
    let isActive: Bool
    let cellSize: CGFloat
    let thumbnailLoader: (Recording) async -> UIImage?

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail or placeholder
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusSm)
                    .strokeBorder(
                        isActive ? Theme.yellow : Color.clear,
                        lineWidth: 2
                    )
            }

            // Duration badge
            Text(recording.formattedDuration)
                .font(Theme.font10Medium)
                .foregroundStyle(Theme.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
        }
        .task {
            thumbnail = await thumbnailLoader(recording)
        }
    }
}
