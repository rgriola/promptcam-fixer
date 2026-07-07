// July 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Photo library change monitor
// Wraps PHPhotoLibraryChangeObserver with a debouncing callback so the
// carousel refreshes when videos are added/removed by ANY source —
// PromptCam's own save, deletes in Photos.app, iCloud sync, etc.

import Foundation
import Photos

/// Testable seam over `PHPhotoLibrary.shared()` register/unregister so
/// tests can drive change notifications without a real photo library.
protocol PhotoLibraryObservable: AnyObject, Sendable {
    func register(_ observer: PHPhotoLibraryChangeObserver)
    func unregister(_ observer: PHPhotoLibraryChangeObserver)
}

/// Production implementation backed by `PHPhotoLibrary.shared()`.
final class DefaultPhotoLibraryObservable: PhotoLibraryObservable, @unchecked Sendable {
    func register(_ observer: PHPhotoLibraryChangeObserver) {
        PHPhotoLibrary.shared().register(observer)
    }
    func unregister(_ observer: PHPhotoLibraryChangeObserver) {
        PHPhotoLibrary.shared().unregisterChangeObserver(observer)
    }
}

/// Watches the Photo Library for changes and fires a debounced callback so
/// the carousel refreshes without polling. Handles the app's own recording
/// saves, external deletes (Photos.app), and iCloud sync.
///
/// Thread notes:
/// - `PHPhotoLibraryChangeObserver.photoLibraryDidChange(_:)` is delivered
///   on an arbitrary queue; we hop to the main actor before touching state.
/// - Debounce coalesces rapid bursts (e.g., iCloud sync) into one refresh.
final class PhotoLibraryChangeMonitor: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {

    /// How long to wait after the last change before firing the callback.
    /// 200 ms is short enough to feel instant and long enough to swallow
    /// bursts from iCloud sync.
    private let debounceInterval: TimeInterval

    private let library: PhotoLibraryObservable

    /// Main-actor callback fired when the library changes (after debounce).
    private var onChange: (@MainActor @Sendable () -> Void)?

    /// Set true only while registered. Protects against double register.
    private var isRegistered = false

    /// The most recent debounce task. Cancelled when a new change arrives.
    private var pendingTask: Task<Void, Never>?

    init(
        library: PhotoLibraryObservable = DefaultPhotoLibraryObservable(),
        debounceInterval: TimeInterval = 0.2
    ) {
        self.library = library
        self.debounceInterval = debounceInterval
        super.init()
    }

    deinit {
        // Best-effort unregister. Safe to call even if already unregistered.
        library.unregister(self)
    }

    /// Starts observing the photo library. Callback fires on the main actor
    /// after the debounce interval has elapsed since the last change.
    /// Idempotent — a second call is a no-op if already started.
    @MainActor
    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        guard !isRegistered else { return }
        self.onChange = onChange
        library.register(self)
        isRegistered = true
    }

    /// Stops observing and cancels any pending debounced callback.
    @MainActor
    func stop() {
        guard isRegistered else { return }
        library.unregister(self)
        isRegistered = false
        pendingTask?.cancel()
        pendingTask = nil
        onChange = nil
    }

    // MARK: - PHPhotoLibraryChangeObserver

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // PHChange is not Sendable and the callback is nonisolated — hop to
        // main to safely touch our debounce state and fire the callback.
        Task { @MainActor [weak self] in
            self?.scheduleDebouncedFire()
        }
    }

    // MARK: - Debounce

    @MainActor
    private func scheduleDebouncedFire() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let ns = UInt64(self.debounceInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            self.onChange?()
        }
    }
}
