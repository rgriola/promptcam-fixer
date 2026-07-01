// PromptCam — Recording Player View
// Full-screen video review with custom playback controls.
// Uses AVPlayerHostingView (AVPlayerViewController, showsPlaybackControls = false)
// so no native AirPlay / PiP icons appear. All chrome is ours.
import AVKit
import Combine
import SwiftUI

struct RecordingPlayerView: View {

    @Environment(\.dismiss) private var dismiss

    /// The recording currently loaded in the player.
    let recording: Recording
    let videoURL: URL?
    let onDelete: () -> Void

    /// Carousel data — first 8 recent recordings passed from the ViewModel.
    /// Empty by default so the view is backward-compatible with existing callers.
    var recentRecordings: [Recording] = []
    /// Loads a thumbnail for a carousel cell on demand.
    var thumbnailLoader: ((Recording) async -> UIImage?)? = nil
    /// Resolves a Recording to a playable URL — called when the carousel selects a new item.
    var resolveURL: ((Recording) async -> URL?)? = nil
    /// Called after a carousel selection so the parent ViewModel can stay in sync.
    var onSelectRecording: ((Recording, URL?) async -> Void)? = nil

    // MARK: - Player State

    @State private var activeRecording: Recording
    @State private var activeURL: URL?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1        // 1 to avoid divide-by-zero
    @State private var showControls = true
    @State private var showDeleteConfirmation = false
    @State private var hideControlsTask: Task<Void, Never>?

    /// Periodic time observer token — stored so we can remove it on disappear.
    @State private var timeObserverToken: Any?

    /// Live horizontal drag offset while swiping to navigate.
    @State private var swipeDragOffset: CGFloat = 0
    /// True once the gesture is confirmed as horizontal (locks out vertical).
    @State private var isHorizontalSwipe = false

    init(
        recording: Recording,
        videoURL: URL?,
        onDelete: @escaping () -> Void,
        recentRecordings: [Recording] = [],
        thumbnailLoader: ((Recording) async -> UIImage?)? = nil,
        resolveURL: ((Recording) async -> URL?)? = nil,
        onSelectRecording: ((Recording, URL?) async -> Void)? = nil
    ) {
        self.recording = recording
        self.videoURL = videoURL
        self.onDelete = onDelete
        self.recentRecordings = recentRecordings
        self.thumbnailLoader = thumbnailLoader
        self.resolveURL = resolveURL
        self.onSelectRecording = onSelectRecording
        self._activeRecording = State(initialValue: recording)
        self._activeURL = State(initialValue: videoURL)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.bgGrad.ignoresSafeArea()

            // ── Video Surface ──────────────────────────────────────────────
            if let player {
                AVPlayerHostingView(player: player)
                    .ignoresSafeArea()
                    .offset(x: swipeDragOffset * 0.15) // subtle parallax while swiping
                    .onTapGesture { togglePlayPause() }
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                let dx = value.translation.width
                                let dy = value.translation.height
                                // Lock to horizontal once the gesture is clearly lateral.
                                if !isHorizontalSwipe {
                                    guard abs(dx) > abs(dy) * 1.5 else { return }
                                    isHorizontalSwipe = true
                                }
                                swipeDragOffset = dx
                            }
                            .onEnded { value in
                                defer {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        swipeDragOffset = 0
                                    }
                                    isHorizontalSwipe = false
                                }
                                guard isHorizontalSwipe else { return }
                                let threshold: CGFloat = 80
                                let dx = value.translation.width
                                if dx < -threshold {
                                    navigateToAdjacent(offset: +1)   // swipe left → next
                                } else if dx > threshold {
                                    navigateToAdjacent(offset: -1)   // swipe right → prev
                                }
                            }
                    )
            } else {
                loadingView
            }

            // ── Swipe navigation hint ────────────────────────────────────────────────
            if abs(swipeDragOffset) > 40 {
                HStack {
                    if swipeDragOffset > 0 { // swiping right → prev
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.4), radius: 6)
                            .padding(.leading, Theme.space24)
                        Spacer()
                    } else {                  // swiping left → next
                        Spacer()
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.4), radius: 6)
                            .padding(.trailing, Theme.space24)
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: swipeDragOffset)
            }

            // ── Control Overlay ────────────────────────────────────────────
            if showControls {
                controlOverlay
                  .transition(.opacity)
            }
        }
        // ── Player Lifecycle ───────────────────────────────────────────────
        .task(id: activeURL) {
            await loadPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
        // ── Delete Confirmation ────────────────────────────────────────────
        .confirmationDialog(
            "Delete Recording",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Video will be permanently deleted.")
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: Theme.space16) {
            ProgressView().tint(Theme.primaryText)
            Text("Pulling video…")
                .font(Theme.font16Regular)
                .foregroundStyle(Theme.primaryText)
        }
    }

    /// Transparent overlay containing top action bar + bottom playback controls.
    private var controlOverlay: some View {
        VStack {
            topBar
            Spacer()
            bottomControls
            // Carousel sits below the playback controls, above the home indicator.
            if !recentRecordings.isEmpty, let loader = thumbnailLoader {
                RecordingCarouselView(
                    recordings: recentRecordings,
                    activeRecordingID: activeRecording.id,
                    thumbnailLoader: loader,
                    onSelect: { selected in
                        Task { await selectRecording(selected) }
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showControls)
    }

    // MARK: - Top Bar: Close / Share / Delete

    private var topBar: some View {
        HStack(spacing: Theme.space16) {
            // Close
            Button {
                dismiss()
            } label: {
                controlIcon("xmark.circle.fill", tint: Theme.primaryText)
            }
            .accessibilityLabel("Close")

            Spacer()

            // Share
            shareButton

            // Delete
            Button {
                showDeleteConfirmation = true
            } label: {
                controlIcon("trash.circle.fill", tint: Theme.red)
            }
            .accessibilityLabel("Delete recording")
        }
        .padding(.horizontal, Theme.space16)
        .padding(.top, Theme.space8)
    }

    // MARK: - Bottom: Play/Pause + Scrubber + Time

    private var bottomControls: some View {
        VStack(spacing: 10) {
            // Scrubber
            scrubber

            // Play row: elapsed — play/pause — remaining
            HStack {
                Text(formatTime(currentTime))
                    .font(Theme.mono12Medium)
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .leading)

                Spacer()

                // Play / Pause
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.white)
                        .shadow(color: .black.opacity(0.4), radius: 6)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Spacer()

                Text("-\(formatTime(max(0, duration - currentTime)))")
                    .font(Theme.mono12Medium)
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, Theme.space16)
        .padding(.bottom, 40)           // clears the home indicator
      /*  .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        */
    }

    private var scrubber: some View {
        Slider(
            value: Binding(
                get: { currentTime },
                set: { newValue in
                    seek(to: newValue)
                }
            ),
            in: 0...max(duration, 0.001)
        )
        .tint(Theme.yellow)
        .accessibilityLabel("Playback position")
    }

    // MARK: - Share Button

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

    // MARK: - Icon Helper

    private func controlIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 32))
            .foregroundStyle(tint)
            .shadow(color: .black.opacity(0.35), radius: 5)
    }

    // MARK: - Player Lifecycle

    // MARK: - Navigation Helpers

    /// Navigates to the recording adjacent to the current one.
    /// `offset` = +1 for next, -1 for previous.
    private func navigateToAdjacent(offset: Int) {
        guard !recentRecordings.isEmpty,
              let currentIndex = recentRecordings.firstIndex(where: { $0.id == activeRecording.id })
        else { return }

        let targetIndex = currentIndex + offset
        guard recentRecordings.indices.contains(targetIndex) else { return }
        let target = recentRecordings[targetIndex]

        Task { await selectRecording(target) }
    }

    /// Shared logic for both carousel taps and video swipes.
    /// Updates activeRecording, resolves the URL, loads the player, and
    /// notifies the parent ViewModel.
    private func selectRecording(_ selected: Recording) async {
        activeRecording = selected
        activeURL = nil                                   // show loading spinner
        let url = await resolveURL?(selected)
        activeURL = url                                   // triggers loadPlayer()
        await onSelectRecording?(selected, url)
    }

    @MainActor
    private func loadPlayer() async {
        guard let url = activeURL else { return }

        // Tear down any previous player cleanly.
        teardownPlayer()

        let p = AVPlayer(url: url)
        player = p

        // Read duration.
        if let item = p.currentItem {
            let d = try? await item.asset.load(.duration)
            if let d, d.isNumeric {
                duration = d.seconds
            }
        }

        // Periodic time observer — updates scrubber every 0.1 s.
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let token = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            // queue: .main guarantees main-thread execution — assumeIsolated is safe here.
            MainActor.assumeIsolated {
                guard let p else { return }
                currentTime = time.seconds
                isPlaying = p.rate > 0
                // Auto-hide controls after video ends.
                if time.seconds >= duration - 0.2 {
                    isPlaying = false
                }
            }
        }
        timeObserverToken = token

        // Start paused — let the user tap play when ready.
        isPlaying = false
        showControls = true
    }

    private func teardownPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 1
    }

    // MARK: - Playback Control

    private func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            showControls = true
            hideControlsTask?.cancel()
        } else {
            // Restart from beginning if at the end.
            if currentTime >= duration - 0.5 {
                player.seek(to: .zero)
                currentTime = 0
            }
            player.play()
            isPlaying = true
            scheduleControlsHide()
        }
    }

    private func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        showControls = true
        scheduleControlsHide()
    }

    // MARK: - Controls Auto-Hide
    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    // MARK: - Time Formatting
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - VideoFile (Transferable for ShareLink)

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
            importing: { _ in
                // Export-only — importing not supported in this app.
                throw CocoaError(.fileReadUnknown)
            }
        )
    }
}
