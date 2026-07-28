// PromptCam — Recording Player View
// Full-screen video review with custom playback controls.
// Uses AVPlayerHostingView (AVPlayerViewController, showsPlaybackControls = false)
// so no native AirPlay / PiP icons appear. All chrome is ours.
// July 8, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add iCloud download progress UI
// July 8, 2026 - GitHub Copilot (Claude Opus 4.7) - Phase 1: cancel in-flight PHImageRequestID,
//     observe AVPlayerItem.status, add 60s resolve timeout, id: on fallback .task
// July 8, 2026 - GitHub Copilot (Claude Opus 4.7) - Delete confirmation stays in player view
// July 8, 2026 - GitHub Copilot (Claude Opus 4.7) - Auto-advance to next video after delete
import AVKit
import Combine
import Photos
import QuartzCore
import SwiftUI

struct RecordingPlayerView: View {

    @Environment(\.dismiss) private var dismiss

    /// Delete callback. Receives the **currently-active** recording (the one
    /// visible in the player at the moment the user confirmed delete) — NOT
    /// the recording the view was initially opened with. Passing it as a
    /// parameter (rather than closing over the init recording) prevents the
    /// data-loss bug where swiping the carousel to video B and then tapping
    /// trash would delete video A because the outer closure captured the
    /// initial recording at construction time.
    let onDelete: (Recording) -> Void

    /// Carousel data — first 8 recent recordings passed from the ViewModel.
    /// Empty by default so the view is backward-compatible with existing callers.
    var recentRecordings: [Recording] = []
    /// Loads a thumbnail for a carousel cell on demand.
    var thumbnailLoader: ((Recording) async -> UIImage?)? = nil
    /// Loads a screen-sized still used for the prev/next drag peek slots.
    /// Falls back to thumbnailLoader when nil (may upscale a small thumbnail).
    var coverThumbnailLoader: ((Recording) async -> UIImage?)? = nil
    /// Resolves a Recording to a playable URL — called when the carousel selects a new item.
    var resolveURL: ((Recording) async -> URL?)? = nil
    /// Same as `resolveURL` but reports iCloud download progress (0.0–1.0)
    /// while the video is being fetched from iCloud. When both are provided,
    /// this one is used; the progress-less variant is kept for callers that
    /// don't need download UI.
    ///
    /// A reference-type `PlayerProgressReporter` is used instead of a raw
    /// closure to sidestep Swift 6's non-escaping-through-closure-boundary
    /// restrictions on the progressHandler.
    ///
    /// The third parameter is an `onStart` callback fired synchronously with
    /// the `PHImageRequestID` as soon as PhotoKit begins the request. This
    /// lets the player store the ID so it can cancel the in-flight download
    /// on dismiss, timeout, or when the user swipes to a different clip —
    /// preventing the orphaned-request leak that used to accumulate on rapid
    /// open/close cycles.
    var resolveURLWithProgress: ((Recording, PlayerProgressReporter, @escaping @Sendable (PHImageRequestID) -> Void) async -> URL?)? = nil
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

    /// iCloud download progress (0.0–1.0) while a video is being fetched.
    /// Nil when no download is in flight. Drives the progress bar shown in
    /// `loadingView` so users see progress instead of a silent black screen.
    @State private var downloadProgress: Double? = nil

    /// Set true when a resolveURL attempt returned nil — used to show the
    /// "video unavailable" state instead of an infinite spinner. Reset when
    /// the user swipes to a different recording.
    @State private var loadFailed: Bool = false

    /// Periodic time observer token — stored so we can remove it on disappear.
    @State private var timeObserverToken: Any?

    /// KVO observation for `AVPlayerItem.status`. Set in `loadPlayer()` for
    /// every new item and invalidated on the next swap / teardown. Catches
    /// `.failed` items so the UI shows the unavailable state instead of a
    /// silent black screen.
    @State private var statusObservation: NSKeyValueObservation?

    /// In-flight PhotoKit request ID for the currently-resolving iCloud
    /// download. Set as soon as `resolveURL` starts (via the `onStart`
    /// callback) and cleared when the resolve completes normally. Cancelled
    /// on player dismiss, next-recording swipe, or 60s timeout so orphaned
    /// downloads don't accumulate in the background.
    @State private var inFlightRequestID: PHImageRequestID?

    // MARK: - Full-screen pager state
    // Same mechanic as RecordingCarouselView, scaled up:
    //   slot width = screen width, spacing = 0
    //   slot[i] center = i * screenWidth  →  active slot at screenWidth * activeIndex
    //   total offset = dragOffset  (baseOffset is always 0 since active slot is always 0)
    //   prev slot lives at -screenWidth + dragOffset
    //   next slot lives at +screenWidth + dragOffset

    /// Live horizontal drag offset (0 when settled).
    @State private var dragOffset: CGFloat = 0
    /// Direction-lock flag — true once the current gesture is confirmed horizontal.
    /// Reset in commitDrag so the next gesture re-evaluates.
    @State private var isHorizontalDrag = false
    /// Cached thumbnail for the recording before the active one (drag peek).
    @State private var prevThumbnail: UIImage?
    /// Cached thumbnail for the recording after the active one (drag peek).
    @State private var nextThumbnail: UIImage?

    // MARK: - Pager Tuning

    private enum PagerConstants {
        /// Velocity (pt/s) above which a flick commits navigation.
        static let velocityThreshold: CGFloat = 600
        /// Minimum drag distance required alongside velocity for a commit.
        static let minCommitDistance: CGFloat = 50
        /// Ratio |dx|/|dy| above which the gesture is considered horizontal.
        static let horizontalLockRatio: CGFloat = 1.5
        /// Rubber-band factor for over-drag at the first/last recording.
        static let rubberBandFactor: CGFloat = 0.15
    }

    init(
        recording: Recording,
        videoURL: URL?,
        onDelete: @escaping (Recording) -> Void,
        recentRecordings: [Recording] = [],
        thumbnailLoader: ((Recording) async -> UIImage?)? = nil,
        coverThumbnailLoader: ((Recording) async -> UIImage?)? = nil,
        resolveURL: ((Recording) async -> URL?)? = nil,
        resolveURLWithProgress: ((Recording, PlayerProgressReporter, @escaping @Sendable (PHImageRequestID) -> Void) async -> URL?)? = nil,
        onSelectRecording: ((Recording, URL?) async -> Void)? = nil
    ) {
        self.onDelete = onDelete
        self.recentRecordings = recentRecordings
        self.thumbnailLoader = thumbnailLoader
        self.coverThumbnailLoader = coverThumbnailLoader
        self.resolveURL = resolveURL
        self.resolveURLWithProgress = resolveURLWithProgress
        self.onSelectRecording = onSelectRecording
        self._activeRecording = State(initialValue: recording)
        self._activeURL = State(initialValue: videoURL)
    }

    // MARK: - Body

    var body: some View {
        ZStack {

            // ── Full-screen pager ──────────────────────────────────────────
            // Slot[i] center = i * screenWidth. Active slot is always slot 0.
            // prev slot lives at -screenWidth + dragOffset
            // next slot lives at +screenWidth + dragOffset
            GeometryReader { geo in
                let w = geo.size.width

                ZStack {
                    // Previous slot
                    if let thumb = prevThumbnail {
                        Image(uiImage: thumb)
                            .resizable().scaledToFill()
                            .frame(width: w, height: geo.size.height).clipped()
                            .offset(x: -w + dragOffset)
                    }

                    // Next slot
                    if let thumb = nextThumbnail {
                        Image(uiImage: thumb)
                            .resizable().scaledToFill()
                            .frame(width: w, height: geo.size.height).clipped()
                            .offset(x: w + dragOffset)
                    }

                    // Active slot — live player or loading view
                    Group {
                        if let player {
                            AVPlayerHostingView(player: player)
                                // Lock the SwiftUI frame so it doesn't inherit
                                // AVPlayerViewController.preferredContentSize
                                // (which changes with each new item's natural size).
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .transition(.identity)
                                .onTapGesture { togglePlayPause() }
                        } else {
                            loadingView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(.identity)
                        }
                    }
                    .transition(.identity)
                    .offset(x: dragOffset)
                }
                .ignoresSafeArea()
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in updateDrag(value) }
                        .onEnded { value in commitDrag(value, width: w) }
                )
                .task(id: activeRecording.id) {
                    await loadAdjacentThumbnails()
                }
            }
            .ignoresSafeArea()

            // ── Control Overlay ────────────────────────────────────────────
            if showControls {
                controlOverlay
                  .transition(.opacity)
            }
        }
        // ── Player Lifecycle ───────────────────────────────────────────────
        .task(id: activeURL) {
            loadPlayer()
        }
        .task(id: activeRecording.id) {
            // If the initial URL was nil (e.g. iCloud video whose prefetch
            // hadn't finished when the player was opened), kick off a resolve
            // so the progress UI can show up instead of an infinite spinner.
            // Keyed on activeRecording.id so it re-runs when the user swipes
            // to a new clip whose URL isn't already resolved.
            guard activeURL == nil else { return }
            let url = await resolveURLWithReporting(activeRecording)
            activeURL = url
            if url == nil { loadFailed = true }
            await onSelectRecording?(activeRecording, url)
        }
        .onChange(of: recentRecordings) { _, newRecordings in
            // Post-delete sync. The parent gallery has already computed the
            // next-active recording atomically and mutated `latestRecording`
            // + `recentRecordings` in a single main-actor transaction.
            //
            // Our job is to reflect that decision — never to re-decide.
            // Racing the parent (via a parallel Task { selectRecording(...))
            // is what used to crash under Swift 6 concurrency when the
            // AVPlayer teardown and the parent view re-render overlapped.
            //
            // Fast path — active still exists: nothing to do (a different
            // recording was deleted, or the user swiped independently).
            let isActiveStillInList = newRecordings.contains { $0.id == activeRecording.id }
            guard !isActiveStillInList else { return }

            // Empty library: parent will drop `latestRecording` to nil and
            // flip `showDirectPlayer` to false. Dismiss here so the player
            // tears down cleanly instead of lingering on a deleted asset.
            guard !newRecordings.isEmpty else {
                dismiss()
                return
            }

            // In-place sync — the parent's `latestRecording` is now the
            // next-active pick. Cancel any in-flight resolve and swap the
            // active recording identity; the `.task(id: activeRecording.id)`
            // observer will start a fresh URL resolve without spawning a
            // competing Task from here.
            //
            // Clear the AVPlayer's current item **before** the resolve
            // begins so the user does not see the deleted video's last
            // decoded frame during the resolve window. Without this, the
            // AVPlayerLayer retains and renders the last frame of the just-
            // deleted asset until `replaceCurrentItem` fires with the new
            // URL — which on iCloud clips can be several seconds.
            cancelInFlightResolve()
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            isPlaying = false
            currentTime = 0
            duration = 1
            let next = newRecordings.first!
            activeRecording = next
            activeURL = nil        // triggers re-resolve via .task(id: activeURL)
            loadFailed = false
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
            Button("Delete", role: .destructive) { onDelete(activeRecording) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently deleting this video.")
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: Theme.space16) {
            if loadFailed {
                // resolveURL returned nil — asset unavailable (deleted, iCloud
                // fetch failed, or no network). Show an actionable error state.
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 42))
                    .foregroundStyle(Theme.primaryText)
                Text("Video not available")
                    .font(Theme.font16Semibold)
                    .foregroundStyle(Theme.primaryText)
                Text("Download it from Photos, then try again.")
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.space24)
            } else if let progress = downloadProgress {
                // iCloud download in flight — show percentage + linear progress.
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.primaryText)
                Text("Downloading from iCloud")
                    .font(Theme.font16Regular)
                    .foregroundStyle(Theme.primaryText)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.primaryText)
                    .frame(maxWidth: 220)
                Text("\(Int(progress * 100))%")
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ProgressView().tint(Theme.primaryText)
                Text("Queuing up video…")
                    .font(Theme.font16Regular)
                    .foregroundStyle(Theme.primaryText)
            }
        }
    }

    /// Controls for Video Player UI
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
                        selectRecording(selected)
                    }
                )
            }
        }
    }


    // MARK: - Top Bar: Close / Share / Delete
    private var topBar: some View {
        HStack(spacing: Theme.space16) {
            // Close
            Button {
                dismiss()
            } label: {
                controlIcon(
                    "xmark.circle.fill", 
                    tint: Theme.primaryText
                    )
            }
            .accessibilityLabel("Close")

            Spacer()

            // Share
            shareButton

            // Delete
            Button {
                showDeleteConfirmation = true
            } label: {
                controlIcon("trash.circle.fill", tint: Theme.primaryText)
            }
            .accessibilityLabel("Delete recording")
        }
        .padding(.horizontal, Theme.space16)
        .padding(.top, Theme.space8)
    }

    // MARK: - Bottom: Play/Pause + Scrubber + Time

    private var bottomControls: some View {
        VStack(spacing: 10) {
             
            // Play row: elapsed — play/pause — remaining
            HStack {
                Text(formatTime(currentTime))
                    .font(Theme.mono16Medium)
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .leading)  

                Spacer()
           
                Text("-\(formatTime(max(0, duration - currentTime)))")
                    .font(Theme.mono16Medium)
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }

            HStack{
                // Play / Pause
                Button {
                    togglePlayPause()
                } label: {
                    Image(
                        systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(Theme.icon44)
                        .foregroundStyle(Theme.white)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                // Scrubber
                scrubber
            }

        }
        .padding(.top, Theme.space12)
        .padding(.horizontal, Theme.space16)
        .padding(.bottom, Theme.space16)// clears the home indicator
        .background(Theme.black.opacity(0.1))
        .frame(maxWidth: .infinity)
            
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
        .accessibilityLabel("Playback position")
    }

    // MARK: - Share Button

    private var shareButton: some View {
        ShareLink(
            item: VideoFile(url: activeURL ?? URL(fileURLWithPath: "")),
            preview: SharePreview(activeRecording.formattedDuration)
        ) {
            controlIcon(
                "square.and.arrow.up.circle.fill",
                tint: Theme.primaryText
            )
        }
        .disabled(activeURL == nil)
        .animation(nil, value: activeURL)
    }

    // MARK: - Icon Helper

    private func controlIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .symbolRenderingMode(.palette)
            .font(Theme.icon44)
            .foregroundStyle(Theme.black, tint)
            //.foregroundStyle(Theme.white)      
    }

    // MARK: - Player Lifecycle
    // MARK: - Navigation Helpers

    private var prevRecording: Recording? {
        guard let i = recentRecordings.firstIndex(where: { $0.id == activeRecording.id }),
              i > 0 else { return nil }
        return recentRecordings[i - 1]
    }

    private var nextRecording: Recording? {
        guard let i = recentRecordings.firstIndex(where: { $0.id == activeRecording.id }),
              i < recentRecordings.count - 1 else { return nil }
        return recentRecordings[i + 1]
    }

    /// Loads thumbnails for the slots immediately before and after the active recording.
    /// Prefers coverThumbnailLoader (screen-sized) if provided so covers don't upscale
    /// from the small carousel thumbnail.
    private func loadAdjacentThumbnails() async {
        let loader = coverThumbnailLoader ?? thumbnailLoader
        prevThumbnail = prevRecording != nil ? await loader?(prevRecording!) : nil
        nextThumbnail = nextRecording != nil ? await loader?(nextRecording!) : nil
    }

    // MARK: - Drag Handlers

    /// Updates `dragOffset` while the user is dragging.
    /// Locks to horizontal once the gesture direction is clear, and
    /// applies rubber-banding at the first/last recording.
    private func updateDrag(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height

        if !isHorizontalDrag {
            guard abs(dx) > abs(dy) * PagerConstants.horizontalLockRatio else { return }
            isHorizontalDrag = true
        }

        let atLeftEdge  = dx > 0 && prevRecording == nil
        let atRightEdge = dx < 0 && nextRecording == nil
        dragOffset = (atLeftEdge || atRightEdge)
            ? dx * PagerConstants.rubberBandFactor
            : dx
    }

    /// On release: commit to prev/next if past threshold, otherwise snap back.
    private func commitDrag(_ value: DragGesture.Value, width w: CGFloat) {
        defer { isHorizontalDrag = false }

        let dx = value.translation.width
        let vx = value.velocity.width
        let threshold = w / 3
        let minDx = PagerConstants.minCommitDistance
        let vt = PagerConstants.velocityThreshold

        if (dx < -threshold || (vx < -vt && dx < -minDx)), let next = nextRecording {
            commitNavigation(to: next)
        } else if (dx > threshold || (vx > vt && dx > minDx)), let prev = prevRecording {
            commitNavigation(to: prev)
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = 0 }
        }
    }

    /// Commit flow — mirrors the carousel tap behavior exactly:
    /// springs `dragOffset` back to 0 while `selectRecording` runs in
    /// parallel. The AVPlayer item is swapped in place, so there is no
    /// offscreen slide and no thumbnail cover — matching the carousel path.
    private func commitNavigation(to target: Recording) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            dragOffset = 0
        }
        selectRecording(target)
    }

    /// Shared logic for both carousel taps and video swipes.
    /// Updates `activeRecording`, resolves the URL, loads the player, and
    /// notifies the parent ViewModel.
    ///
    /// Does NOT set `activeURL = nil` first — that would flip the Group to
    /// the loadingView branch and destroy the AVPlayerViewController,
    /// causing the UIKit appearance animation on the next player. Instead
    /// `loadPlayer` reuses the existing player via `replaceCurrentItem`.
    private func selectRecording(_ selected: Recording) {
        // Cancel any in-flight resolve from the previous recording so we don't
        // leak PhotoKit requests as the user rapidly swipes through the carousel.
        cancelInFlightResolve()
        loadFailed = false                                // reset before new attempt
        activeURL = nil                                   // triggers .task(id: activeRecording.id)
        activeRecording = selected
    }

    /// Cancels an in-flight PhotoKit resolve request, if any, and clears the
    /// stored ID. Safe to call when no request is pending. Called from
    /// `selectRecording` (before starting a new resolve), the 60s timeout,
    /// and `teardownPlayer` (on view disappear).
    @MainActor
    private func cancelInFlightResolve() {
        guard let id = inFlightRequestID else { return }
        PHImageManager.default().cancelImageRequest(id)
        inFlightRequestID = nil
    }

    /// Resolves a Recording's URL, preferring the progress-reporting closure
    /// when it's available. Manages `downloadProgress` so the loading view
    /// can show a progress bar for iCloud downloads.
    ///
    /// Wraps the resolve in a 60s timeout: if PhotoKit hasn't returned by
    /// then (e.g. stalled iCloud download), the in-flight request is
    /// cancelled via `PHImageManager.cancelImageRequest` and nil is returned
    /// so the loading view flips to the "video unavailable" state instead of
    /// spinning forever.
    @MainActor
    private func resolveURLWithReporting(_ recording: Recording) async -> URL? {
        // Reset the placeholder — 0.0 shows an empty progress bar so the user
        // sees SOMETHING is happening even before the first progressHandler fires.
        downloadProgress = 0.0
        defer {
            downloadProgress = nil
            // Clear the stored ID once the resolve returns — the request is
            // either complete or already cancelled by the timeout branch.
            inFlightRequestID = nil
        }

        // The onStart closure fires synchronously from inside the resolve
        // closure as soon as PhotoKit begins the request. Storing the ID here
        // (not after the await returns) is what makes mid-flight cancellation
        // actually work — by the time the await returns, the request is done.
        let onStart: @Sendable (PHImageRequestID) -> Void = { id in
            Task { @MainActor in
                self.inFlightRequestID = id
            }
        }

        let resolveTask = Task<URL?, Never> { [resolveURLWithProgress, resolveURL] in
            if let progressLoader = resolveURLWithProgress {
                let reporter = PlayerProgressReporter { fraction in
                    Task { @MainActor in
                        self.downloadProgress = fraction
                    }
                }
                return await progressLoader(recording, reporter, onStart)
            } else {
                // Progress-less fallback: no early-notify path available, so
                // timeout cancellation via ID isn't possible for this branch.
                // The timeout still fires and returns nil so the UI recovers.
                return await resolveURL?(recording)
            }
        }

        // Race the resolve against a 60s timeout. If the timeout wins, cancel
        // the in-flight PhotoKit request so it doesn't keep downloading in the
        // background. Note we can't `throw` from a Never-throwing task, so we
        // use a nullable URL and treat timeout as nil.
        //
        // Task is a value type wrapping an internal handle, so capturing it
        // strongly here does not create a retain cycle — the timeout closure
        // is discarded once this function returns.
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await MainActor.run { self.cancelInFlightResolve() }
            resolveTask.cancel()
        }

        let url = await resolveTask.value
        timeoutTask.cancel()
        return url
    }

    @MainActor
    private func loadPlayer() {
        guard let url = activeURL else { return }

        let item = AVPlayerItem(url: url)
        // Cap the forward buffer at 5s so playback starts sooner on
        // slow/cellular networks. No-op for local file URLs (the whole file
        // is the buffer) but relevant if resolveURL ever returns a streaming
        // URL (e.g. .mediumQualityFormat / HLS). Default is 0 meaning
        // "AVPlayer decides" \u2014 typically a much larger buffer which delays
        // first-frame on slow networks. Set on every item since AVPlayerItem
        // is recreated per swap.
        item.preferredForwardBufferDuration = 5

        // Install a status observer BEFORE handing the item to the player so
        // we catch `.failed` transitions even if they fire immediately (e.g.
        // invalid URL, deleted file). Previously, a failed item silently left
        // the user on a black screen with no error UI.
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new]) { observedItem, _ in
            let status = observedItem.status
            Task { @MainActor in
                if status == .failed {
                    loadFailed = true
                    player?.pause()
                    isPlaying = false
                }
            }
        }

        if let existing = player {
            // Reuse the existing AVPlayer — swap the item so
            // AVPlayerViewController stays in the view hierarchy.
            // No VC recreation → no UIKit appearance animation → no zoom flash.
            existing.pause()

            // Suppress AVPlayerLayer's implicit CALayer animation for the
            // aspect-fit transform. Without this, when a new item's natural
            // size differs from the previous one, the layer briefly renders
            // stretched-to-bounds then animates to .resizeAspect over ~0.25s
            // — which reads as a visible zoom-in on the incoming video.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            existing.replaceCurrentItem(with: item)
            existing.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { _ in })
            CATransaction.commit()
        } else {
            // First load — create the player and install the time observer once.
            let p = AVPlayer(playerItem: item)
            player = p
            installTimeObserver(on: p)
        }

        // Reset per-item UI state.
        currentTime = 0
        duration = 1
        isPlaying = false
        showControls = true

        Task {
            let d = try? await item.asset.load(.duration)
            if let d, d.isNumeric {
                await MainActor.run { duration = d.seconds }
            }
        }
    }

    /// Installs the periodic time observer. Only called once per player
    /// instance since we now reuse the same AVPlayer across items.
    private func installTimeObserver(on p: AVPlayer) {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let token = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            // queue: .main guarantees main-thread execution — assumeIsolated is safe here.
            MainActor.assumeIsolated {
                guard let p else { return }
                currentTime = time.seconds
                isPlaying = p.rate > 0
                if time.seconds >= duration - 0.2 {
                    isPlaying = false
                }
            }
        }
        timeObserverToken = token
    }

    /// Full teardown — only called on view disappear. Never called between
    /// item swaps, so the AVPlayerViewController is not recreated.
    ///
    /// Strict order (MainActor-isolated so no cross-actor teardown races):
    ///   1. Cancel in-flight PhotoKit resolve — no late-arriving URL will
    ///      fire a `.task` update on this view after tear-down starts.
    ///   2. Invalidate the AVPlayerItem status KVO so its callback can't
    ///      post a MainActor `Task` after the observer has been dropped.
    ///   3. Remove the periodic time observer before nilling the player —
    ///      calling `removeTimeObserver` after `player = nil` crashes with
    ///      "-[AVPlayer removeTimeObserver:] token was not returned by ...".
    ///   4. Pause + nil the player, so any queued CALayer transactions
    ///      finish on a still-valid AVPlayer object.
    ///   5. Cancel the controls-hide task last; it references view state
    ///      but not the player, so ordering is not strict.
    @MainActor
    private func teardownPlayer() {
        cancelInFlightResolve()

        statusObservation?.invalidate()
        statusObservation = nil

        if let token = timeObserverToken, let p = player {
            p.removeTimeObserver(token)
        }
        timeObserverToken = nil

        player?.pause()
        player = nil

        hideControlsTask?.cancel()
        hideControlsTask = nil

        isPlaying = false
        currentTime = 0
        duration = 1

        RecordingsService().stopCachingAll()
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
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 2.0)) { 
                            showControls = false }
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

// MARK: - Progress Reporter

/// Reference-type wrapper around a progress callback so it can be safely
/// escaped across closure boundaries in Swift 6. Function-typed closure
/// parameters cannot be marked `@escaping` when they appear inside another
/// closure type — passing one to a function that stores it (e.g.
/// PHVideoRequestOptions.progressHandler) triggers a non-escaping-parameter
/// compile error. Wrapping the callback in a Sendable class sidesteps that.
final class PlayerProgressReporter: Sendable {
    private let callback: @Sendable (Double) -> Void

    init(callback: @escaping @Sendable (Double) -> Void) {
        self.callback = callback
    }

    /// Report a progress value (0.0–1.0). Safe to call from any thread.
    func report(_ fraction: Double) {
        callback(fraction)
    }
}
