// PromptCam — Recording Carousel
// Fixed-center carousel: the active item is always at screen center.
// Uses a DragGesture on an offset HStack rather than a ScrollView so
// the snap target is the CENTER of each cell, not its leading edge.
//
// Offset math:
//   centerInitial = (screenWidth - cellWidth) / 2
//   HStack.offset  = centerInitial + baseOffset + dragOffset
//
//   When baseOffset = -i * slotWidth, item i's center sits at:
//   (screenWidth - cellWidth)/2 + cellWidth/2 = screenWidth/2  ✓
import Photos
import SwiftUI

/// A fixed-center horizontal carousel of video thumbnails.
///
/// The active recording's cell is permanently anchored at screen center.
/// Dragging moves adjacent cells into center; on release the nearest cell
/// spring-snaps to center and `onSelect` is called for that recording.
struct RecordingCarouselView: View {

    let recordings: [Recording]
    let activeRecordingID: String
    let thumbnailLoader: (Recording) async -> UIImage?
    let onSelect: (Recording) -> Void

    private let cellWidth:  CGFloat = 84
    private let cellHeight: CGFloat = 84
    private let spacing:    CGFloat = 10
    private var slotWidth:  CGFloat { cellWidth + spacing }

    /// Offset index: baseOffset = -i * slotWidth centers item i.
    @State private var baseOffset: CGFloat = 0
    /// Live drag translation added on top of baseOffset.
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            // Offset so item 0's left edge starts at (screenWidth-cellWidth)/2,
            // placing item 0's center at screenWidth/2.
            let centerInitial = (geo.size.width - cellWidth) / 2
            let totalOffset   = centerInitial + baseOffset + dragOffset

            HStack(spacing: spacing) {
                ForEach(Array(recordings.enumerated()), 
                         id: \.element.id) { index, recording in
                    let isActive = recording.id == activeRecordingID

                    CarouselCell(
                        recording: recording,
                        isActive: isActive,
                        cellWidth: cellWidth,
                        cellHeight: cellHeight,
                        thumbnailLoader: thumbnailLoader
                    )
                    .scaleEffect(isActive ? 1.0 : 0.82)
                    .opacity(isActive ? 1.0 : 0.55)
                    // withAnimation isolates this spring so it doesn't bleed
                    // into the parent ZStack / full-screen player.
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isActive)
                    .onTapGesture {
                        guard !isActive else { return }
                        onSelect(recording)
                    }
                }
            }
            .offset(x: totalOffset)
            .contentShape(Rectangle())
            // Drag scrolls the strip; velocity-aware snap on lift.
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let velocity    = value.velocity.width
                        let rawIndex    = -(baseOffset + dragOffset) / slotWidth
                        var targetIndex: Int

                        if velocity > 300 {
                            targetIndex = Int(floor(rawIndex))      // flick right → prev
                        } else if velocity < -300 {
                            targetIndex = Int(ceil(rawIndex))       // flick left → next
                        } else {
                            targetIndex = Int(round(rawIndex))
                        }
                        targetIndex = max(0, min(recordings.count - 1, targetIndex))

                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            baseOffset = -CGFloat(targetIndex) * slotWidth
                            dragOffset = 0
                        }
                        onSelect(recordings[targetIndex])
                    }
            )
            // Scroll active item to center when selection changes from outside.
            .onChange(of: activeRecordingID) { _, newID in
                if let index = recordings.firstIndex(where: { $0.id == newID }) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        baseOffset = -CGFloat(index) * slotWidth
                        dragOffset = 0
                    }
                }
            }
            .onAppear {
                // No animation on initial positioning.
                if let index = recordings.firstIndex(where: { $0.id == activeRecordingID }) {
                    baseOffset = -CGFloat(index) * slotWidth
                }
            }
        }
        .frame(height: cellHeight + Theme.space16)
        .clipped()  // hide overflow cells that extend beyond the visible strip
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
    /// Incremented to re-trigger the .task when a retry is needed.
    @State private var loadAttempt = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Placeholder while iCloud thumbnail is loading.
                    // Shows a subtle spinner to signal "loading, not missing".
                    Color.white.opacity(0.12)
                        .overlay(
                            ZStack {
                                Image(systemName: "icloud.and.arrow.down")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                        )
                }
            }
            .frame(width: cellWidth, height: cellHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(
                        isActive ? Theme.accent : Theme.white.opacity(0.2),
                        lineWidth: isActive ? 2 : 1
                    )
            }

            Text(recording.formattedDuration)
                .font(Theme.font10Medium)
                .foregroundStyle(Theme.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Theme.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                .padding(5)
        }
        .task(id: loadAttempt) {
            let result = await thumbnailLoader(recording)
            if let result {
                thumbnail = result
            } else if thumbnail == nil {
                // iCloud fetch returned nil — schedule a retry after a short
                // delay so cells don't stay blank for users with slow iCloud sync.
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                loadAttempt += 1
            }
        }
    }
}
