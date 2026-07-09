// July 9, 2026 - GitHub Copilot (Claude Opus 4.7)
// Pure math helpers for the RecordingCarouselView drag/snap behavior.
// Kept free of SwiftUI so it can be unit-tested without a host view.

import CoreGraphics

/// Pure functions describing the carousel's snap/centering math.
///
/// - Fixed-center layout: item[i] centers at screen center when the parent
///   HStack is offset by `centerInitial + baseOffset(forIndex: i)`.
/// - `baseOffset(forIndex: i) == -CGFloat(i) * slotWidth`.
///
/// This helper exists so the view's drag/reorder logic is unit-testable.
/// The SwiftUI view retains all gesture plumbing; it only defers arithmetic
/// and threshold checks here.
enum CarouselDragMath {

     /// Base offset that places the item at `index` at screen center.
     static func baseOffset(forIndex index: Int, slotWidth: CGFloat) -> CGFloat {
          -CGFloat(index) * slotWidth
     }

     /// Direction-lock predicate. Returns true when a drag translation is
     /// clearly horizontal enough that the carousel should capture it (and
     /// deny the underlying pager). Vertical/diagonal drags fall through.
     ///
     /// - Parameter ratio: `|dx| / |dy|` threshold. Loose enough (1.2) to
     ///   still feel grippy without stealing near-vertical swipes.
     static func shouldEngageHorizontal(
          dx: CGFloat, dy: CGFloat, ratio: CGFloat = 1.2
     ) -> Bool {
          let absDx = abs(dx)
          let absDy = abs(dy)
          // A purely horizontal drag with dy == 0 must always engage.
          guard absDy > 0 else { return absDx > 0 }
          return absDx > absDy * ratio
     }

     /// Given a drag end event, computes the target snap index within
     /// [0, count-1]. Uses velocity to bias flicks in the drag direction.
     ///
     /// - Parameters:
     ///   - baseOffset: current `baseOffset` before drag.
     ///   - dragOffset: accumulated translation at release.
     ///   - slotWidth: cell width + spacing.
     ///   - velocity: horizontal velocity in pt/s at release.
     ///   - count: total number of items.
     static func targetIndex(
          baseOffset: CGFloat,
          dragOffset: CGFloat,
          slotWidth: CGFloat,
          velocity: CGFloat,
          count: Int
     ) -> Int {
          guard count > 0, slotWidth > 0 else { return 0 }
          let rawIndex = -(baseOffset + dragOffset) / slotWidth
          let velocityThreshold: CGFloat = 300
          var target: Int
          if velocity > velocityThreshold {
               target = Int(floor(rawIndex))  // flick right -> prev
          } else if velocity < -velocityThreshold {
               target = Int(ceil(rawIndex))  // flick left -> next
          } else {
               target = Int(rawIndex.rounded())
          }
          return max(0, min(count - 1, target))
     }
}
