// July 17, 2026 - GitHub Copilot - Extracted modal/sheet queue from CameraViewModel
import Foundation

/// Serializes sheet presentation for the camera screen.
///
/// SwiftUI allows only one `.sheet` presenter at a time. If a second modal is
/// requested while one is active, the request is queued and dequeued when the
/// active modal dismisses. This prevents the "sheet not presented" bug that
/// occurs with rapid modal switching.
///
/// **@MainActor**: `activeSheet` drives a SwiftUI `.sheet(item:)` binding.
@MainActor
@Observable
final class ModalQueue {
    /// The currently presented sheet, bound by the view's `.sheet(item:)`.
    var activeSheet: CameraSheetRoute?

    /// The most recently presented sheet, retained until dismissal is handled
    /// so the coordinator can react to *which* sheet just closed.
    @ObservationIgnored private(set) var lastPresentedSheet: CameraSheetRoute?

    @ObservationIgnored private var queuedSheet: CameraSheetRoute?

    /// Presents `route`, or queues it if a sheet is already active.
    func present(_ route: CameraSheetRoute) {
        guard activeSheet == nil else {
            queuedSheet = route
            return
        }

        // .composeScript is routed through showComposeSheet / fullScreenCover
        // to prevent the camera preview from being rescaled.

        lastPresentedSheet = route
        activeSheet = route
    }

    /// Dismisses the active sheet.
    func dismissActive() {
        activeSheet = nil
    }

    /// Finalizes a dismissal: clears `lastPresentedSheet` and presents any
    /// queued sheet. Call after the coordinator has reacted to
    /// `lastPresentedSheet`.
    func finishDismissal() {
        lastPresentedSheet = nil
        presentQueuedIfNeeded()
    }

    private func presentQueuedIfNeeded() {
        guard activeSheet == nil, let route = queuedSheet else { return }
        queuedSheet = nil
        present(route)
    }
}
