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
    /// Registers this view's frame under `id` in the `"cameraOverlay"` coordinate space
    /// for the feature tour to use as a spotlight target.
    ///
    /// Using a named coordinate space (set on the CameraView ZStack) ensures frames
    /// and overlay positions share the same origin, avoiding safe-area offset mismatches.
    func tourAnchor(_ id: String) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TourAnchorKey.self,
                    value: [id: geo.frame(in: .named("cameraOverlay"))]
                )
            }
        )
    }
}
