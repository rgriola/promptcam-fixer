// July 17, 2026 - GitHub Copilot - Extracted recording timer from CameraViewModel
import Combine
import Foundation

/// Drives the recording duration display for the camera screen. Extracted from
/// `CameraViewModel` so the coordinator stays thin.
///
/// Computes elapsed time from a start date rather than accumulating increments,
/// which avoids floating-point drift over long recordings.
///
/// **@MainActor**: `duration` drives SwiftUI; the Combine timer fires on the
/// main run loop.
@MainActor
@Observable
final class RecordingTimer {
    /// Recording duration in seconds, updated every 0.1s while running.
    var duration: TimeInterval = 0

    @ObservationIgnored private var timerCancellable: AnyCancellable?
    @ObservationIgnored private var startDate: Date?

    /// Starts the timer, resetting the elapsed duration to zero.
    func start() {
        duration = 0
        startDate = Date()
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.startDate else { return }
                self.duration = Date().timeIntervalSince(start)
            }
        Log.viewmodel.debug("Recording timer started")
    }

    /// Stops and resets the timer.
    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        startDate = nil
        duration = 0
        Log.viewmodel.debug("Recording timer stopped")
    }
}
