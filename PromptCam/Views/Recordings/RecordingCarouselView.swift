// PromptCam — Recording Carousel
// Centered paging carousel below the player timeline.
// Active item is centered; neighbors stage left and right.
// Uses ScrollViewReader + .scrollTargetBehavior(.viewAligned) for
// native iOS paging snap (iOS 17+, deployment target is iOS 18).
import Photos
import SwiftUI

/// A horizontally scrolling, center-snapping carousel of video thumbnails.
///
/// - The active recording is centered in the frame and shown at full scale.
/// - Neighboring recordings peek in from either side at reduced opacity/scale.
/// - Selecting any cell calls `onSelect` and the caller drives the centering
///   by updating `activeRecordingID`, which triggers an animated scroll.
struct RecordingCarouselView: View {

    let recordings: [Recording]
    let activeRecordingID: String
    let thumbnailLoader: (Recording) async -> UIImage?
    let onSelect: (Recording) -> Void

    // Cell dimensions — taller than the old strip to give the centered
    // item visual weight comparable to the native iOS player.
    private let cellWidth:  CGFloat = 84
    private let cellHeight: CGFloat = 84
    private let spacing:    CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            // Side inset so the first and last cells can be centered.
            let sideInset = (geo.size.width - cellWidth) / 2

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(recordings) { recording in
                            let isActive = recording.id == activeRecordingID
                            CarouselCell(
                                recording: recording,
                                isActive: isActive,
                                cellWidth: cellWidth,
                                cellHeight: cellHeight,
                                thumbnailLoader: thumbnailLoader
                            )
                            .id(recording.id)
                            .scaleEffect(isActive ? 1.0 : 0.82)
                            .opacity(isActive ? 1.0 : 0.55)
                            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isActive)
                            .onTapGesture { onSelect(recording) }
                        }
                    }
                    .padding(.horizontal, sideInset)
                    // Registers each cell as a scroll target for view-aligned snapping.
                    .scrollTargetLayout()
                }
                // Snap to the nearest cell center on lift.
                .scrollTargetBehavior(.viewAligned)
                .onAppear {
                    // Scroll to active without animation on first appearance.
                    proxy.scrollTo(activeRecordingID, anchor: .center)
                }
                .onChange(of: activeRecordingID) { _, newID in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
        .frame(height: cellHeight + Theme.space16)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
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
    let cellWidth: CGFloat
    let cellHeight: CGFloat
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
                    Color.white.opacity(0.12)
                        .overlay(
                            Image(systemName: "video.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.white.opacity(0.3))
                        )
                }
            }
            .frame(width: cellWidth, height: cellHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(
                        isActive ? Theme.yellow : Theme.white.opacity(0.2),
                        lineWidth: isActive ? 2 : 1
                    )
            }

            // Duration badge
            Text(recording.formattedDuration)
                .font(Theme.font10Medium)
                .foregroundStyle(Theme.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                .padding(5)
        }
        .task {
            thumbnail = await thumbnailLoader(recording)
        }
    }
}
