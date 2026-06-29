// PromptCam — Feature Tour Coordinator
// June 26, 2026 - @Observable coordinator that drives step navigation and tour state.
// June 29, 2026 - Removed withAnimation from model methods (caused animation-context
//                poisoning when @Observable mutation triggered mid-preference-accumulation).
import SwiftUI
import Observation
import OSLog

/// Manages active state and step navigation for the feature tour.
///
/// Instantiate once in `CameraView` as `@State private var tourCoordinator = TourCoordinator()`.
/// Start the tour by calling `start(required:)`. Step through with `next()` / `back()`. Dismiss with `end()`.
@Observable
final class TourCoordinator {

    // MARK: - State

    /// Whether the tour overlay is currently visible.
    var isActive = false

    /// Zero-based index of the current step.
    private(set) var currentIndex: Int = 0

    /// When `true`, the Skip button is hidden — user must advance through all steps.
    /// Set to `true` for the mandatory first-use tour.
    private(set) var isRequired: Bool = false

    /// The ordered steps for the current tour run.
    private(set) var steps: [TourStep] = []

    // MARK: - Derived

    var currentStep: TourStep? {
        guard currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    var isFirst: Bool { currentIndex == 0 }
    var isLast:  Bool { currentIndex == steps.count - 1 }

    /// Human-readable progress label, e.g. "2 of 6".
    var progress: String { "\(currentIndex + 1) of \(steps.count)" }

    // MARK: - Actions

    /// Begin the tour.
    /// - Parameters:
    ///   - steps: Steps to walk through. Defaults to `TourCatalog.essentials`.
    ///   - required: When `true` the Skip button is hidden. Use for the first-use tour.
    func start(steps: [TourStep] = TourCatalog.essentials, required: Bool = false) {
        // Guard against re-entry: a second tap while the tour is already visible
        // would otherwise reset currentIndex mid-animation and corrupt state.
        guard !isActive else {
            Log.ui.warning("[Tour] start() blocked — already active (step \(self.currentIndex, privacy: .public))")
            return
        }
        self.steps = steps
        self.currentIndex = 0
        self.isRequired = required
        // NOTE: No withAnimation here. Setting isActive synchronously lets SwiftUI
        // apply the .transition() defined at the call site (CameraView overlay)
        // without injecting an animation context that poisons preference-key accumulation.
        self.isActive = true
        Log.ui.debug("[Tour] started — steps=\(steps.count, privacy: .public) required=\(required, privacy: .public)")
    }

    /// Advance to the next step, or end the tour if already on the last step.
    func next() {
        guard !isLast else { end(); return }
        // Animation context lives here, not in the model — driving index change
        // triggers view updates which animate via .animation(value:) at the overlay.
        currentIndex += 1
        Log.ui.debug("[Tour] next → step \(self.currentIndex, privacy: .public) of \(self.steps.count, privacy: .public)")
    }

    /// Go back to the previous step. No-op on the first step.
    func back() {
        guard !isFirst else {
            Log.ui.warning("[Tour] back() called on first step — no-op")
            return
        }
        currentIndex -= 1
        Log.ui.debug("[Tour] back → step \(self.currentIndex, privacy: .public) of \(self.steps.count, privacy: .public)")
    }

    /// Dismiss the tour overlay.
    func end() {
        // Synchronous — animation is handled by the .transition() at the view layer.
        isActive = false
        // Reset step so the next start() always opens cleanly at step 1.
        currentIndex = 0
        Log.ui.debug("[Tour] ended — isActive=false, index reset to 0")
    }
}
