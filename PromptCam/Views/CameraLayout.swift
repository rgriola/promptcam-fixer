// May 29, 2026 - 11:23pm - GitHub Copilot
import SwiftUI

enum CameraLayout {
    static let previewAspect: CGFloat = 9.0 / 16.0
    // Points of vertical drag to traverse the full +/- exposure range (10 EV total)
    static let evFullRangePoints: CGFloat = 120

    static func barHeights(containerSize: CGSize) -> (barHeight: CGFloat, previewHeight: CGFloat) {
        let previewHeight = containerSize.width / previewAspect
        let barHeight = max((containerSize.height - previewHeight) / 2, 0)
        return (barHeight, previewHeight)
    }
}

