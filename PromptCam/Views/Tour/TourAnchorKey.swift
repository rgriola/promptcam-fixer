// PromptCam — Tour Anchor Preference Key
// June 26, 2026 - PreferenceKey that collects global frames from spotlight target views.
import SwiftUI

/// Collects `[anchorID: CGRect]` global-coordinate frames from child views.
/// `FeatureTourOverlay` reads these frames to draw spotlight cutouts over the correct elements.
struct TourAnchorKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Registers this view's global-coordinate frame under `id` for the feature tour to spotlight.
    ///
    /// Uses `.global` coordinate space so the frame origin is at the physical screen top-left.
    /// `FeatureTourOverlay` also uses `.ignoresSafeArea()` on its GeometryReader, which reports
    /// full-screen (physical) dimensions — keeping both in the same coordinate space.
    func tourAnchor(_ id: String) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TourAnchorKey.self,
                    value: [id: geo.frame(in: .global)]
                )
            }
        )
    }
}
