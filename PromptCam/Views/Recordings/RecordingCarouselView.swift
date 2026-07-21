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
                    // Force distinct view identity per recording so @State
                    // (thumbnail, loadAttempt, loadFailed) never leaks across
                    // cells when the recordings array reorders, and so the
                    // retry .task inside the cell is cleanly cancelled when
                    // the underlying recording rotates out.
                    .id(recording.id)
                    .scaleEffect(isActive ? 1.0 : 0.82)
                    .opacity(isActive ? 1.0 : 0.55)
                    // withAnimation isolates this spring so it doesn't bleed
                    // into the parent ZStack / full-screen player.
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isActive)
                    // .highPriorityGesture ensures the tap wins over the
                    // parent HStack's DragGesture (minimumDistance: 5). Plain
                    // .onTapGesture was intermittently swallowed when a
                    // natural finger-drift of 5+ pt activated the parent
                    // drag path first — user tapped a non-active cell and
                    // nothing happened.
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            guard !isActive else { return }
                            onSelect(recording)
                        }
                    )
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

                        // Only fire onSelect when the drag actually landed on
                        // a different clip. Without this guard, a tap-like
                        // gesture with a few points of drift would round to
                        // the current active index and call
                        // onSelect(currentActive) — which sets
                        // activeRecording to its existing value, so
                        // .onChange(of: activeRecordingID) never fires and
                        // the user's tap on a NEIGHBOURING cell appeared to
                        // do nothing (the parent drag ate the tap AND then
                        // no-op'd the select).
                        let target = recordings[targetIndex]
                        if target.id != activeRecordingID {
                            onSelect(target)
                        }
                    }
            )
            // Scroll active item to center when selection changes from outside.
            .onChange(of: activeRecordingID) { _, _ in
                scrollActiveToCenter(animated: true)
            }
            // Also re-position when the recordings array itself changes shape
            // (e.g. after a delete). Without this, if the parent's list is
            // mutated but activeRecordingID happens to stay the same (or
            // updates race the recordings change), the index of the active
            // clip can move but the carousel would keep the stale offset —
            // one of the visible symptoms was the carousel not tracking a
            // swipe on the video-player after dismiss/re-open.
            .onChange(of: recordings) { _, _ in
                scrollActiveToCenter(animated: true)
            }
            .onAppear {
                // No animation on initial positioning.
                scrollActiveToCenter(animated: false)
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

    /// Recomputes `baseOffset` so the cell for `activeRecordingID` sits at
    /// screen center. Called from `.onAppear` (no animation), from
    /// `.onChange(of: activeRecordingID)`, and from `.onChange(of: recordings)`
    /// so the strip re-syncs whenever either input changes.
    ///
    /// Reads the current `recordings` and `activeRecordingID` from `self` at
    /// call time — not from a stale closure capture — so it works even when
    /// the parent's list mutates in the same tick as the ID change.
    private func scrollActiveToCenter(animated: Bool) {
        guard let index = recordings.firstIndex(where: { $0.id == activeRecordingID }) else {
            return
        }
        let target = -CGFloat(index) * slotWidth
        guard target != baseOffset else { return }
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                baseOffset = target
                dragOffset = 0
            }
        } else {
            baseOffset = target
            dragOffset = 0
        }
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
    /// Set true once we've exhausted retries and give up.
    /// Stops the infinite retry loop that pegged CPU for iCloud assets
    /// that never resolved (no network, deleted, permissions).
    @State private var loadFailed = false
    /// Tracks whether the thumbnail was originally missing (iCloud-offloaded)
    /// and only appeared after a retry. Used to overlay a cloud badge so
    /// users know the underlying video also lives in iCloud and will need a
    /// download before playback.
    @State private var wasFromCloud = false

    /// Live connectivity state. When the network goes from down to up while
    /// a cell is in `loadFailed`, we reset `loadAttempt` to 0 to re-trigger
    /// the `.task` — lets users regain thumbnails after a network hiccup
    /// without swiping the cell out of view and back.
    @State private var networkMonitor = NetworkMonitor.shared

    /// Retry ceiling. After this many failed attempts we stop trying and
    /// show the unavailable placeholder. Bumped from 2 to 5 (Phase 3) so
    /// slow iCloud downloads have room to complete; each retry still
    /// requires an actual PhotoKit request so the ceiling matters.
    private static let maxRetries = 5
    /// Backoff delays in seconds keyed by attempt index. Extended alongside
    /// the retry ceiling so later attempts don't hammer PhotoKit.
    private static let retryDelays: [UInt64] = [3, 5, 8, 15, 30]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if loadFailed {
                    // Permanent placeholder — no more retries.
                    Color.white.opacity(0.12)
                        .overlay(
                            Image(systemName: "exclamationmark.icloud")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.white.opacity(0.4))
                        )
                } else {
                    // Placeholder while iCloud thumbnail is loading.
                    Color.white.opacity(0.12)
                        .overlay(
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.white.opacity(0.35))
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
            // Cloud badge — shown on cells whose thumbnail needed a retry to
            // load (i.e. was originally iCloud-offloaded). Tells users the
            // underlying video will also require a download before playback,
            // so a delay opening the player is expected, not a bug.
            .overlay(alignment: .topTrailing) {
                if wasFromCloud && thumbnail != nil {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.white)
                        .padding(4)
                        .background(Theme.black.opacity(0.55), in: Circle())
                        .padding(5)
                        .accessibilityLabel("Stored in iCloud")
                }
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
                // If we needed any retries to get here, flag the cell so the
                // cloud badge overlay renders. First-attempt success stays
                // badge-free — the video was already local.
                if loadAttempt > 0 { wasFromCloud = true }
                return
            }
            // Nil result — decide whether to retry or give up.
            guard thumbnail == nil else { return }
            guard loadAttempt < Self.maxRetries else {
                loadFailed = true
                return
            }
            let waitSeconds = Self.retryDelays[loadAttempt]
            try? await Task.sleep(nanoseconds: waitSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            loadAttempt += 1
        }
        // When the network flips from down to up while a cell is in the
        // failed state, reset the retry counter so the .task re-fires. Only
        // recovers cells that gave up — an in-flight retry is unaffected.
        .onChange(of: networkMonitor.isConnected) { _, connected in
            guard connected, loadFailed else { return }
            loadFailed = false
            loadAttempt = 0
        }
    }
}
