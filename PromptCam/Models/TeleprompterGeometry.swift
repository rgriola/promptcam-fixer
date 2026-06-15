import CoreGraphics

/// Pure offset math for the teleprompter. Unit-testable outside SwiftUI.
///
/// Model: first line starts centered (`startOffset`), auto-scroll subtracts
/// until the last line exits the top (`scrollStopOffset`). Manual drag is
/// bounded by `dragCeiling` (can't push text below viewport) and
/// `scrollStopOffset` (can't pull past the end).
struct TeleprompterGeometry: Equatable, Sendable {
    let viewportHeight: CGFloat
    let textHeight: CGFloat
    let fontSize: CGFloat
    let verticalPadding: CGFloat

    /// Approximate single-line height for the current font.
    var lineHeight: CGFloat { fontSize * 1.4 }

    /// First line of script vertically centered in the viewport.
    var centerOffset: CGFloat {
        viewportHeight / 2 - verticalPadding - lineHeight / 2
    }

    /// Convenience alias — the script always starts at center.
    var startOffset: CGFloat { centerOffset }

    /// The offset at which the last line has fully exited past the top edge.
    /// Used as the floor clamp for both auto-scroll and manual drag.
    var scrollStopOffset: CGFloat {
        -(textHeight + verticalPadding)
    }

    /// Upper bound for manual drag: first line can descend at most to
    /// one lineHeight above the viewport bottom edge. Prevents dragging
    /// text so far down that the first line disappears below the viewport.
    var dragCeiling: CGFloat {
        viewportHeight - lineHeight
    }
}
